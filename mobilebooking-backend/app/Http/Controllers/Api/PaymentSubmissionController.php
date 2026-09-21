<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\Supabase\SupabaseRpcException;
use App\Services\Supabase\SupabaseRpcService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;

class PaymentSubmissionController extends Controller
{
    private const BUCKET = 'payment-proofs';

    public function store(Request $request, SupabaseRpcService $supabase): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'booking_id' => ['required', 'uuid'],
            'stage' => ['required', 'string', 'in:down_payment,balance,other'],
            'declared_amount' => ['required', 'numeric', 'min:0.01'],
            'payment_method' => ['nullable', 'string', 'max:255'], // e.g. "gcash"
            'external_reference' => ['nullable', 'string', 'max:255'], // GCash ref number
            'proof' => ['required', 'file', 'mimes:jpg,jpeg,png,pdf', 'max:10240'], // 10MB
        ]);

        if ($validator->fails()) {
            return response()->json([
                'status' => 'error',
                'error' => 'VALIDATION_FAILED',
                'details' => $validator->errors(),
            ], 422);
        }

        $data = $validator->validated();
        $accessToken = $request->attributes->get('supabase_access_token') ?? $request->bearerToken();

        if (blank($accessToken)) {
            return response()->json(['status' => 'error', 'error' => 'UNAUTHENTICATED'], 401);
        }

        /** @var \Illuminate\Http\UploadedFile $file */
        $file = $request->file('proof');

        // Step 1: who is this token for?
        try {
            $user = $supabase->getCurrentUser($accessToken);
        } catch (SupabaseRpcException $e) {
            return $this->mapRpcError($e);
        }

        $userId = $user['id'] ?? null;
        if (blank($userId)) {
            return response()->json(['status' => 'error', 'error' => 'UNAUTHENTICATED'], 401);
        }

        // Step 2: ownership + state checks.
        //
        // IMPORTANT — SECURITY BOUNDARY: the two inserts below go through Laravel's
        // own database connection, which bypasses row-level security (the same way
        // BookingDocumentController and the catalog routes already do). Going through
        // PostgREST as the customer instead failed with Postgres error
        // "infinite recursion detected in policy for relation booking_payment_submissions"
        // — a faulty RLS policy inside Supabase. So these PHP checks are the ONLY
        // thing stopping someone from attaching a payment to somebody else's booking.
        $booking = DB::table('bookings')->where('id', $data['booking_id'])->first();

        if (!$booking) {
            return $this->fail('BOOKING_NOT_FOUND', 'We could not find that booking.', 404);
        }
        if ($booking->customer_id !== $userId) {
            return $this->fail('FORBIDDEN', 'You do not have permission to submit payment for this booking.', 403);
        }
        if (in_array($booking->status, ['cancelled', 'rejected'], true)) {
            return $this->fail('BOOKING_CLOSED', 'This booking is closed and can no longer accept payments.', 409);
        }
        if ($data['stage'] === 'down_payment' && DB::table('booking_payment_submissions')
                ->where('booking_id', $data['booking_id'])
                ->where('stage', 'down_payment')
                ->whereIn('status', ['submitted', 'under_review', 'verified'])
                ->exists()) {
            return $this->fail('ALREADY_SUBMITTED', 'A payment has already been submitted for this booking.', 409);
        }

        // Step 3: upload the actual file bytes to Storage (still as the customer).
        $storagePath = sprintf(
            '%s/%s/%s-%s',
            $userId,
            $data['booking_id'],
            (string) Str::uuid(),
            preg_replace('/[^A-Za-z0-9._-]/', '_', $file->getClientOriginalName()),
        );

        try {
            $supabase->uploadObject(
                bucket: self::BUCKET,
                path: $storagePath,
                contents: file_get_contents($file->getRealPath()),
                mimeType: $file->getMimeType() ?? 'application/octet-stream',
                userAccessToken: $accessToken,
            );
        } catch (SupabaseRpcException $e) {
            return $this->mapRpcError($e);
        }

        // Steps 4 + 5: record the document and the payment submission, atomically.
        // `status` on the submission is deliberately omitted so it takes its default
        // ('submitted') instead of trusting the client.
        try {
            [$document, $submission] = DB::transaction(function () use ($userId, $data, $file, $storagePath) {
                // Make auth.uid() resolve inside this transaction — as PostgREST would —
                // so any column defaults or triggers that call it see the customer.
                DB::select(
                    "select set_config('request.jwt.claims', ?, true), set_config('request.jwt.claim.sub', ?, true)",
                    [json_encode(['sub' => $userId, 'role' => 'authenticated']), $userId],
                );

                $now = now();

                $documentRow = [
                    'id' => (string) Str::uuid(),
                    'owner_user_id' => $userId,
                    'document_type' => 'payment_proof',
                    'storage_bucket' => self::BUCKET,
                    'storage_path' => $storagePath,
                    'original_filename' => $file->getClientOriginalName(),
                    'status' => 'active',
                    'created_at' => $now,
                    'updated_at' => $now,
                ];
                // Only fill these when the table actually has them.
                foreach (['mime_type' => $file->getMimeType(), 'file_size_bytes' => $file->getSize()] as $column => $value) {
                    if (Schema::hasColumn('customer_documents', $column)) {
                        $documentRow[$column] = $value;
                    }
                }
                DB::table('customer_documents')->insert($documentRow);

                $submissionRow = [
                    'id' => (string) Str::uuid(),
                    'booking_id' => $data['booking_id'],
                    'stage' => $data['stage'],
                    'declared_amount' => $data['declared_amount'],
                    'payment_method' => $data['payment_method'] ?? null,
                    'external_reference' => $data['external_reference'] ?? null,
                    'proof_document_id' => $documentRow['id'],
                ];
                foreach (['created_at' => $now, 'updated_at' => $now] as $column => $value) {
                    if (Schema::hasColumn('booking_payment_submissions', $column)) {
                        $submissionRow[$column] = $value;
                    }
                }
                DB::table('booking_payment_submissions')->insert($submissionRow);

                return [$documentRow, $submissionRow];
            });
        } catch (\Throwable $e) {
            report($e);

            // Nothing was committed, so don't leave the uploaded file dangling.
            $supabase->deleteObject(self::BUCKET, $storagePath, $accessToken);

            return $this->fail(
                'PAYMENT_SUBMISSION_FAILED',
                'We could not submit your payment. Please try again.'
                    . (config('app.debug') ? ' [debug: ' . $e->getMessage() . ']' : ''),
                500,
            );
        }

        return response()->json([
            'status' => 'created',
            'data' => [
                'submission' => $submission,
                'document' => $document,
            ],
        ], 201);
    }

    /** Error responses carry a machine `error` code AND a human `message` the app can show. */
    private function fail(string $code, string $message, int $status): JsonResponse
    {
        return response()->json(['status' => 'error', 'error' => $code, 'message' => $message], $status);
    }

    private function mapRpcError(SupabaseRpcException $e): JsonResponse
    {
        $message = $e->getMessage();

        // PostgREST's generic RLS-denial message for a blocked insert.
        if (str_contains($message, 'row-level security') || $e->httpStatus === 403) {
            return response()->json([
                'status' => 'error',
                'error' => 'FORBIDDEN',
                'message' => 'You do not have permission to submit payment for this booking.',
            ], 403);
        }

        if ($e->httpStatus === 401 || $message === 'NOT_AUTHENTICATED') {
            return response()->json([
                'status' => 'error',
                'error' => 'NOT_AUTHENTICATED',
                'message' => 'Your session has expired. Please sign in again.',
            ], 401);
        }

        report($e);

        return response()->json([
            'status' => 'error',
            'error' => 'PAYMENT_SUBMISSION_FAILED',
            'message' => 'We could not submit your payment. Please try again.'
                . (config('app.debug') ? ' [debug: ' . $message . ']' : ''),
            'code' => $message,
        ], 422);
    }
}