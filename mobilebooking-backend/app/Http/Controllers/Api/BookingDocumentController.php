<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\Supabase\SupabaseRpcException;
use App\Services\Supabase\SupabaseRpcService;
use App\Support\BookingStatusDeriver;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;

/**
 * Step 4 + the customer side of Step 5, combined -- confirmed against the
 * real app's two-endpoint flow:
 *   app/api/bookings/[bookingId]/documents/upload/route.ts   -> uploadDocument()
 *   app/api/bookings/[bookingId]/documents/submit/route.ts   -> submitDocuments()
 *
 * They are genuinely one flow, not two steps: verification documents,
 * the six agreement acknowledgements, and the customer's signature are
 * all submitted together in submitDocuments(), after each file has
 * already been uploaded individually via uploadDocument(). There is no
 * separate customer-facing "sign the agreement" endpoint -- that's why
 * BookingAgreementController::store()/show() were retired.
 *
 * Response envelope intentionally matches the real routes'
 * {success, error} / {success, path, bucket} shape (not
 * BookingController's plain {error} shape) -- this endpoint pair is a
 * direct behavioral port, and Flutter's future implementation of
 * submitBookingDocuments()-equivalent will be built against this exact
 * contract, same as bookingSubmissionService.ts was.
 *
 * NOT ported: rate limiting (enforceRateLimit in the real routes) and
 * log_audit_event. Both are flagged omissions, not decisions -- rate
 * limiting needs a Laravel-side mechanism (middleware/throttle) that
 * doesn't exist yet for this route, and log_audit_event's signature was
 * never provided. Neither blocks correctness of the write itself.
 *
 * Writes go through Laravel's own DB connection in a transaction, same
 * as every other write in this codebase -- not through PostgREST/RLS.
 */
class BookingDocumentController extends Controller
{
    private const ID_MIME_TYPES = ['image/jpeg', 'image/png', 'image/webp', 'application/pdf'];
    private const SIGNATURE_MIME_TYPES = ['image/jpeg', 'image/png', 'image/webp'];
    private const MAX_FILE_KB = 4096; // 4MB, matches the real route's MAX_FILE_SIZE

    private const UPLOAD_KINDS = [
        'idOne' => ['fileName' => 'id-one', 'signature' => false],
        'idTwo' => ['fileName' => 'id-two', 'signature' => false],
        'selfie' => ['fileName' => 'selfie', 'signature' => false],
        'emergencyId' => ['fileName' => 'emergency-contact-id', 'signature' => false],
        'signature' => ['fileName' => 'signature', 'signature' => true],
    ];

    private const REUSABLE_SLOT_DOCUMENT_TYPES = [
        'idOne' => 'government_id',
        'idTwo' => 'secondary_id',
        'selfie' => 'selfie_with_id',
    ];

    /**
     * POST /bookings/{bookingId}/documents/upload?kind=...&submissionId=...
     * Multipart, single field: file.
     */
    public function uploadDocument(Request $request, string $bookingId, SupabaseRpcService $supabase): JsonResponse
    {
        $kind = $request->query('kind');
        $submissionId = (string) $request->query('submissionId', '');

        if (!is_string($kind) || !array_key_exists($kind, self::UPLOAD_KINDS)) {
            return response()->json(['success' => false, 'error' => 'The document type is invalid.'], 400);
        }
        if (!preg_match('/^[0-9a-f-]{36}$/i', $submissionId)) {
            return response()->json(['success' => false, 'error' => 'The upload session is invalid.'], 400);
        }

        [$accessToken, $userId, $authError] = $this->authenticate($request, $supabase);
        if ($authError) {
            return $authError;
        }

        $booking = DB::table('bookings')->where('id', $bookingId)->first();
        if (!$booking) {
            return response()->json(['success' => false, 'error' => 'The booking could not be found.'], 404);
        }
        if ($booking->customer_id !== $userId) {
            return response()->json(['success' => false, 'error' => 'You do not have access to this booking.'], 403);
        }
        if (BookingStatusDeriver::requirementsStatus($bookingId) !== 'not_submitted') {
            return response()->json(['success' => false, 'error' => 'Verification documents have already been submitted.'], 409);
        }
        if (!$this->hasSubmittedPayment($bookingId)) {
            return response()->json(['success' => false, 'error' => 'Submit your reservation payment proof before uploading documents.'], 409);
        }

        $file = $request->file('file');
        if (!$file instanceof UploadedFile || $file->getSize() === 0) {
            return response()->json(['success' => false, 'error' => 'Choose a file to upload.'], 400);
        }
        if ($file->getSize() > self::MAX_FILE_KB * 1024) {
            return response()->json(['success' => false, 'error' => 'Each file must be 4MB or smaller.'], 400);
        }

        $kindDef = self::UPLOAD_KINDS[$kind];
        $allowedTypes = $kindDef['signature'] ? self::SIGNATURE_MIME_TYPES : self::ID_MIME_TYPES;
        $mimeType = $file->getMimeType() ?: 'application/octet-stream';
        if (!in_array($mimeType, $allowedTypes, true)) {
            return response()->json(['success' => false, 'error' => 'The selected file type is not supported.'], 400);
        }

        $bucket = $kindDef['signature'] ? 'customer-documents' : 'booking-documents';
        $path = "{$userId}/{$bookingId}/{$kindDef['fileName']}-{$submissionId}." . $this->extensionFor($mimeType);

        try {
            $supabase->uploadObject(
                bucket: $bucket,
                path: $path,
                contents: file_get_contents($file->getRealPath()),
                mimeType: $mimeType,
                userAccessToken: $accessToken,
                upsert: true,
            );
        } catch (SupabaseRpcException $e) {
            report($e);

            return response()->json(['success' => false, 'error' => 'This file could not be securely uploaded.'], 500);
        }

        return response()->json(['success' => true, 'path' => $path, 'bucket' => $bucket]);
    }

    /**
     * POST /bookings/{bookingId}/documents/submit
     * JSON body matching the real app's metadataSchema exactly.
     */
    public function submitDocuments(Request $request, string $bookingId, SupabaseRpcService $supabase): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'submissionId' => ['required', 'uuid'],
            'files.idOne' => ['nullable', 'string', 'min:1'],
            'files.idTwo' => ['nullable', 'string', 'min:1'],
            'files.selfie' => ['nullable', 'string', 'min:1'],
            'files.emergencyId' => ['required', 'string', 'min:1'],
            'files.signature' => ['required', 'string', 'min:1'],
            'reusedDocuments.idOne' => ['nullable', 'uuid'],
            'reusedDocuments.idTwo' => ['nullable', 'uuid'],
            'reusedDocuments.selfie' => ['nullable', 'uuid'],
            'facebookLink' => ['required', 'string', 'url', 'max:1000'],
            'instagramLink' => ['required', 'string', 'url', 'max:1000'],
            'emergencyContact.fullName' => ['required', 'string', 'min:2', 'max:160'],
            'emergencyContact.relationship' => ['required', 'string', 'min:2', 'max:100'],
            'emergencyContact.phone' => ['required', 'string', 'regex:/^\d{11}$/'],
            'emergencyContact.facebookLink' => ['required', 'string', 'url', 'max:1000'],
            'acknowledgements.infoAccurate' => ['required', 'accepted'],
            'acknowledgements.agreedToTerms' => ['required', 'accepted'],
            'acknowledgements.understoodRentalRules' => ['required', 'accepted'],
            'acknowledgements.authorizedESignature' => ['required', 'accepted'],
            'acknowledgements.readPrivacyNotice' => ['required', 'accepted'],
            'acknowledgements.emergencyContactAuthorized' => ['required', 'accepted'],
            'signatureMethod' => ['required', 'string', 'in:drawn,uploaded'],
            'typedFullName' => ['required', 'string', 'min:2', 'max:160'],
        ]);

        if ($validator->fails()) {
            return response()->json(['success' => false, 'error' => 'Check the verification details and agreement, then try again.'], 400);
        }
        $data = $validator->validated();

        // Each reusable slot must be satisfied by exactly one source.
        foreach (self::REUSABLE_SLOT_DOCUMENT_TYPES as $slot => $docType) {
            $hasFile = !empty($data['files'][$slot] ?? null);
            $hasReused = !empty($data['reusedDocuments'][$slot] ?? null);
            if ($hasFile === $hasReused) {
                return response()->json([
                    'success' => false,
                    'error' => 'Each verification document must be either freshly uploaded or reused from your verified records.',
                ], 400);
            }
        }

        [$accessToken, $userId, $authError] = $this->authenticate($request, $supabase);
        if ($authError) {
            return $authError;
        }

        $booking = DB::table('bookings')->where('id', $bookingId)->first();
        if (!$booking) {
            return response()->json(['success' => false, 'error' => 'The booking could not be found.'], 404);
        }
        if ($booking->customer_id !== $userId) {
            return response()->json(['success' => false, 'error' => 'You do not have access to this booking.'], 403);
        }
        if (BookingStatusDeriver::requirementsStatus($bookingId) !== 'not_submitted') {
            return response()->json(['success' => false, 'error' => 'Verification documents have already been submitted.'], 409);
        }
        if (!$this->hasSubmittedPayment($bookingId)) {
            return response()->json(['success' => false, 'error' => 'Submit your reservation payment proof before submitting documents.'], 409);
        }

        // Verify every uploaded path actually exists and lives under this
        // user/booking/submission's own prefix before trusting it.
        try {
            foreach (self::REUSABLE_SLOT_DOCUMENT_TYPES as $slot => $docType) {
                if (!empty($data['files'][$slot] ?? null)) {
                    $this->verifyUploadedFile(
                        $supabase, 'booking-documents', $data['files'][$slot],
                        "{$userId}/{$bookingId}/" . self::UPLOAD_KINDS[$slot]['fileName'] . "-{$data['submissionId']}.",
                        $accessToken,
                    );
                }
            }
            $this->verifyUploadedFile(
                $supabase, 'booking-documents', $data['files']['emergencyId'],
                "{$userId}/{$bookingId}/emergency-contact-id-{$data['submissionId']}.",
                $accessToken,
            );
            $this->verifyUploadedFile(
                $supabase, 'customer-documents', $data['files']['signature'],
                "{$userId}/{$bookingId}/signature-{$data['submissionId']}.",
                $accessToken,
            );
        } catch (\RuntimeException $e) {
            return response()->json(['success' => false, 'error' => 'An uploaded document could not be verified.'], 400);
        } catch (SupabaseRpcException $e) {
            report($e);

            return response()->json(['success' => false, 'error' => 'An uploaded document could not be verified.'], 502);
        }

        // Validate every reused document.
        $reusedSlots = array_filter(
            array_keys(self::REUSABLE_SLOT_DOCUMENT_TYPES),
            fn ($slot) => !empty($data['reusedDocuments'][$slot] ?? null),
        );
        $reusedIds = array_values(array_unique(array_map(fn ($slot) => $data['reusedDocuments'][$slot], $reusedSlots)));

        if (!empty($reusedIds)) {
            $now = now();
            $reusedDocs = DB::table('customer_documents')
                ->whereIn('id', $reusedIds)
                ->where('owner_user_id', $userId)
                ->where('status', 'active')
                ->get()
                ->keyBy('id');
            $approvedIds = DB::table('booking_requirement_submissions')
                ->whereIn('customer_document_id', $reusedIds)
                ->where('review_status', 'approved')
                ->pluck('customer_document_id')
                ->flip();

            foreach ($reusedSlots as $slot) {
                $docId = $data['reusedDocuments'][$slot];
                $doc = $reusedDocs->get($docId);
                $failure = match (true) {
                    !$doc => 'A reused verification document could not be found on your account.',
                    $doc->document_type !== self::REUSABLE_SLOT_DOCUMENT_TYPES[$slot] => 'A reused verification document no longer matches its slot.',
                    !empty($doc->expires_at) && $doc->expires_at <= $now => 'A reused verification document has expired. Please upload a new copy.',
                    !$approvedIds->has($docId) => 'A reused verification document was never approved. Please upload a new copy.',
                    default => null,
                };
                if ($failure) {
                    return response()->json(['success' => false, 'error' => $failure], 400);
                }
            }
        }

        // Booking items, needed for the agreement snapshot.
        $items = DB::table('booking_items as bi')
            ->leftJoin('products as p', 'p.id', '=', 'bi.product_id')
            ->where('bi.booking_id', $bookingId)
            ->select('bi.id as booking_item_id', 'bi.product_name_snapshot', 'bi.daily_rate_snapshot',
                'bi.deposit_per_unit_snapshot', 'bi.quantity', DB::raw('to_jsonb(p) as product_row'))
            ->get();

        $b = DB::table('bookings as b')
            ->leftJoin('booking_fulfillments as bf', 'bf.booking_id', '=', 'b.id')
            ->where('b.id', $bookingId)
            ->select('b.status', 'b.pickup_at', 'b.return_at',
                'bf.method as fulfillment_method', 'bf.address_line_1', 'bf.city_municipality', 'bf.province',
                DB::raw('COALESCE(bf.delivery_fee_snapshot, 0) as delivery_fee'),
                'bf.pickup_convenience_fee_snapshot')
            ->first();

        $profile = DB::table('profiles')->where('id', $userId)->first();
        $dayCount = max(1, (int) DB::selectOne(
            'SELECT GREATEST(1, EXTRACT(day FROM (?::timestamptz - ?::timestamptz)))::int as days',
            [$b->return_at, $b->pickup_at],
        )->days ?? 1);

        // Confirm real unit allocation -- as the customer, never
        // service-role (get_booking_unit_assignments requires auth.uid()).
        try {
            $assignmentRows = $supabase->callMany('get_booking_unit_assignments', ['p_booking_id' => $bookingId], $accessToken);
        } catch (SupabaseRpcException $e) {
            report($e);

            return response()->json(['success' => false, 'error' => 'Your reserved units could not be confirmed. Please try again.'], 502);
        }
        $activeStatuses = ['tentative', 'confirmed', 'in_use'];
        $assignmentsByItem = [];
        foreach ($assignmentRows as $row) {
            $assignmentsByItem[$row['booking_item_id']][] = $row;
        }
        foreach ($items as $item) {
            $active = array_filter(
                $assignmentsByItem[$item->booking_item_id] ?? [],
                fn ($a) => in_array($a['reservation_status'], $activeStatuses, true),
            );
            if (count($active) !== (int) $item->quantity) {
                return response()->json([
                    'success' => false,
                    'error' => 'Your reserved units could not be fully confirmed. Please contact support before signing.',
                ], 409);
            }
        }

        $fulfillmentMethod = $b->fulfillment_method ?? 'pickup';
        $customerLocation = $fulfillmentMethod === 'pickup'
            ? 'Pickup — Right Focus Off Campus, Manuel Hizon, Sta. Cruz, Manila'
            : implode(', ', array_filter([$b->address_line_1, $b->city_municipality, $b->province]));

        $rentalSubtotal = 0.0;
        $depositAmount = 0.0;
        $snapshotItems = [];
        foreach ($items as $item) {
            $dailyRate = (float) $item->daily_rate_snapshot;
            $lineTotal = $dailyRate * $item->quantity * $dayCount;
            $rentalSubtotal += $lineTotal;
            $depositAmount += (float) $item->deposit_per_unit_snapshot * $item->quantity;

            // Whole product row as JSON: tolerant of columns this table doesn't have (e.g. brand).
            $productRow = $item->product_row ? (json_decode($item->product_row, true) ?: []) : [];
            $specs = $productRow['specifications'] ?? [];
            if (is_string($specs)) {
                $specs = json_decode($specs, true) ?: [];
            }
            if (!is_array($specs)) {
                $specs = [];
            }
            $included = (!empty($specs['included']) && is_string($specs['included']))
                ? array_values(array_filter(array_map('trim', explode(',', $specs['included']))))
                : [];

            $units = array_map(
                fn ($a) => ['unitCode' => $a['unit_code'], 'serialNumber' => $a['serial_number']],
                array_filter($assignmentsByItem[$item->booking_item_id] ?? [], fn ($a) => in_array($a['reservation_status'], $activeStatuses, true)),
            );

            $snapshotItems[] = [
                'productName' => $item->product_name_snapshot,
                'brand' => (string) ($productRow['brand'] ?? ''),
                'quantity' => (int) $item->quantity,
                'pricePerDay' => $dailyRate,
                'rentalDays' => $dayCount,
                'lineTotal' => $lineTotal,
                'includedAccessories' => $included,
                'units' => array_values($units),
            ];
        }

        $deliveryFee = (float) $b->delivery_fee;
        $pickupConvenienceFee = (float) ($b->pickup_convenience_fee_snapshot ?? 0);
        // ASSUMPTION FLAGGED: like BookingController, discountAmount can't
        // be reconstructed -- p_discount_amount is accepted by the create
        // RPC but never persisted anywhere Laravel can read it back from.
        $discountAmount = 0.0;
        $finalAmount = $rentalSubtotal + $deliveryFee + $pickupConvenienceFee - $discountAmount;

        $agreementSnapshot = [
            'customerName' => trim((string) ($profile->display_name ?? '')) ?: $data['typedFullName'],
            'items' => $snapshotItems,
            'startDate' => $b->pickup_at,
            'endDate' => $b->return_at,
            'dayCount' => $dayCount,
            'fulfillmentMethod' => $fulfillmentMethod,
            'customerLocation' => $customerLocation,
            'currency' => 'PHP',
            'subtotal' => $rentalSubtotal,
            'discountAmount' => $discountAmount,
            'depositAmount' => $depositAmount,
            'fees' => $deliveryFee + $pickupConvenienceFee,
            'finalAmount' => $finalAmount,
        ];

        try {
            DB::transaction(function () use ($data, $userId, $bookingId, $items, $agreementSnapshot, $reusedSlots, $b) {
                $now = now();

                $documentSlots = [
                    ['slot' => 'idOne', 'type' => 'government_id', 'label' => 'Primary Government ID'],
                    ['slot' => 'idTwo', 'type' => 'secondary_id', 'label' => 'Secondary ID'],
                    ['slot' => 'selfie', 'type' => 'selfie_with_id', 'label' => 'Selfie with ID'],
                    ['slot' => 'emergencyId', 'type' => 'authorization_letter', 'label' => 'Emergency Contact ID'],
                ];

                // Insert only the FRESH ones -- reused slots point at an
                // existing customer_documents row, not a new one.
                $freshSlots = array_filter($documentSlots, fn ($def) => $def['slot'] === 'emergencyId' || !in_array($def['slot'], $reusedSlots, true));
                $documentIdBySlot = [];
                foreach ($freshSlots as $def) {
                    $id = (string) Str::uuid();
                    DB::table('customer_documents')->insert([
                        'id' => $id,
                        'owner_user_id' => $userId,
                        'document_type' => $def['type'],
                        'storage_bucket' => 'booking-documents',
                        'storage_path' => $data['files'][$def['slot']],
                        'original_filename' => self::UPLOAD_KINDS[$def['slot']]['fileName'],
                        'status' => 'active',
                        'created_at' => $now,
                        'updated_at' => $now,
                    ]);
                    $documentIdBySlot[$def['slot']] = $id;
                }
                foreach ($reusedSlots as $slot) {
                    $documentIdBySlot[$slot] = $data['reusedDocuments'][$slot];
                }

                $requirementIds = [];
                foreach ($documentSlots as $def) {
                    $requirementIds[$def['slot']] = DB::table('booking_requirements')->insertGetId([
                        'id' => (string) Str::uuid(),
                        'booking_id' => $bookingId,
                        'document_type_snapshot' => $def['type'],
                        'requirement_key_snapshot' => $def['type'],
                        'requirement_name_snapshot' => $def['label'],
                        'is_required' => true,
                        'status' => 'pending_review',
                        'created_at' => $now,
                        'updated_at' => $now,
                    ], 'id');
                }

                foreach ($documentSlots as $def) {
                    DB::table('booking_requirement_submissions')->insert([
                        'id' => (string) Str::uuid(),
                        'booking_requirement_id' => $requirementIds[$def['slot']],
                        'customer_document_id' => $documentIdBySlot[$def['slot']],
                        'review_status' => 'pending',
                        'submitted_at' => $now,
                        'updated_at' => $now,
                    ]);
                }

                $agreementId = (string) Str::uuid();
                DB::table('booking_agreements')->insert([
                    'id' => $agreementId,
                    'booking_id' => $bookingId,
                    'status' => 'awaiting_business_signature',
                    'created_by' => $userId,
                    'created_at' => $now,
                    'updated_at' => $now,
                ]);

                $versionId = (string) Str::uuid();
                DB::table('agreement_versions')->insert([
                    'id' => $versionId,
                    'agreement_id' => $agreementId,
                    'version_number' => 1,
                    'status' => 'awaiting_business_signature',
                    'agreement_snapshot' => json_encode($agreementSnapshot),
                    'generated_at' => $now,
                    'created_by' => $userId,
                    'created_at' => $now,
                ]);

                foreach ($data['acknowledgements'] as $key => $value) {
                    DB::table('agreement_acknowledgements')->insert([
                        'id' => (string) Str::uuid(),
                        'agreement_version_id' => $versionId,
                        'user_id' => $userId,
                        'acknowledgement_key' => $key,
                        'acknowledged' => true,
                        'acknowledged_at' => $now,
                    ]);
                }

                DB::table('agreement_signatures')->insert([
                    'id' => (string) Str::uuid(),
                    'agreement_version_id' => $versionId,
                    'signer_user_id' => $userId,
                    'signer_role' => 'customer',
                    'signer_name' => $data['typedFullName'],
                    'signature_path' => $data['files']['signature'],
                    'signature_data' => json_encode(['method' => $data['signatureMethod']]),
                    'signed_at' => $now,
                ]);

                // NOTE: the real route also validates+accepts
                // emergencyContact.facebookLink but never stores it
                // anywhere -- only fullName/relationship/phone/address
                // land in booking_emergency_contacts. Matching that
                // behavior exactly rather than "fixing" it, since this is
                // a contract port, not a redesign; worth raising with
                // whoever owns the real app if that's unintentional.
                DB::table('booking_emergency_contacts')->updateOrInsert(
                    ['booking_id' => $bookingId],
                    [
                        'full_name' => $data['emergencyContact']['fullName'],
                        'relationship' => $data['emergencyContact']['relationship'],
                        'phone_number' => $data['emergencyContact']['phone'],
                        'address' => '',
                        'updated_at' => $now,
                    ],
                );

                DB::table('booking_status_history')->insert([
                    'id' => (string) Str::uuid(),
                    'booking_id' => $bookingId,
                    'from_status' => $b->status,
                    'to_status' => $b->status,
                    'note' => 'Customer submitted verification documents and signed the rental agreement.',
                    'changed_by' => $userId,
                    'created_at' => $now,
                ]);
            });
        } catch (\Throwable $e) {
            report($e);

            return response()->json(['success' => false, 'error' => 'The documents could not be finalized. Please try again.'], 500);
        }

        return response()->json(['success' => true]);
    }

    /** @return array{0: ?string, 1: ?string, 2: ?JsonResponse} */
    private function authenticate(Request $request, SupabaseRpcService $supabase): array
    {
        $accessToken = $request->attributes->get('supabase_access_token') ?? $request->bearerToken();
        if (blank($accessToken)) {
            return [null, null, response()->json(['success' => false, 'error' => 'You need to be signed in.'], 401)];
        }
        try {
            $user = $supabase->getCurrentUser($accessToken);
        } catch (SupabaseRpcException $e) {
            return [null, null, response()->json(['success' => false, 'error' => 'Your session has expired. Please sign in again.'], 401)];
        }
        $userId = $user['id'] ?? null;
        if (blank($userId)) {
            return [null, null, response()->json(['success' => false, 'error' => 'Could not resolve your account.'], 401)];
        }

        return [$accessToken, $userId, null];
    }

    private function hasSubmittedPayment(string $bookingId): bool
    {
        return DB::table('booking_payment_submissions')
            ->where('booking_id', $bookingId)
            ->whereIn('status', ['submitted', 'under_review', 'verified'])
            ->exists();
    }

    private function verifyUploadedFile(SupabaseRpcService $supabase, string $bucket, string $path, string $expectedPrefix, string $accessToken): void
    {
        if (!str_starts_with($path, $expectedPrefix) || str_contains(substr($path, strlen($expectedPrefix)), '/')) {
            throw new \RuntimeException('INVALID_DOCUMENT_PATH');
        }
        $folder = substr($path, 0, strrpos($path, '/'));
        $fileName = substr($path, strrpos($path, '/') + 1);
        $entries = $supabase->listObjects($bucket, $folder, $accessToken, $fileName);
        if (!collect($entries)->contains(fn ($e) => ($e['name'] ?? null) === $fileName)) {
            throw new \RuntimeException('DOCUMENT_NOT_VERIFIED');
        }
    }

    private function extensionFor(string $mimeType): string
    {
        return match ($mimeType) {
            'image/png' => 'png',
            'image/webp' => 'webp',
            'application/pdf' => 'pdf',
            default => 'jpg',
        };
    }
}