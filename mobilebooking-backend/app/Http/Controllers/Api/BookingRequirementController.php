<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\Supabase\SupabaseRpcException;
use App\Services\Supabase\SupabaseRpcService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;

/**
 * Step 4 — verification documents.
 *
 * index()  unchanged from the original draft: lists a booking's
 *          requirements through SupabaseRpcService::select(), which goes
 *          via PostgREST using the customer's own token. RLS
 *          (customers_read_own_booking_requirements) is what actually
 *          scopes this to the caller's own bookings.
 *
 * store()  REWRITTEN. The original version called a new
 *          submit_booking_requirement_document() Postgres RPC function,
 *          which would have required a schema change on Supabase. Per
 *          project constraints, nothing may be changed on the Supabase
 *          side right now, so this version does the same work entirely
 *          in Laravel instead: it uses Laravel's own direct DB
 *          connection (the same connection the /catalog and
 *          /availability-check routes in routes/api.php already use)
 *          inside a DB::transaction(), and does the ownership /
 *          status / document-type checks in PHP rather than in a
 *          Postgres function.
 *
 *          IMPORTANT — SECURITY BOUNDARY MOVED: Laravel's DB connection
 *          here bypasses RLS entirely, the same way the existing
 *          catalog/availability routes already do. That means the
 *          checks in this method (booking ownership, document
 *          ownership, document status, document-type match) are the
 *          ONLY thing enforcing correctness for this write — there is
 *          no RLS policy underneath it as a backstop. A bug in this
 *          method is a real authorization bug, not just a display bug.
 *          If that trade-off isn't acceptable, the RPC-function version
 *          from earlier in this session is the safer alternative, but
 *          it requires a Postgres migration.
 */
class BookingRequirementController extends Controller
{
    public function index(Request $request, SupabaseRpcService $supabase, string $bookingId): JsonResponse
    {
        $accessToken = $request->attributes->get('supabase_access_token') ?? $request->bearerToken();

        if (blank($accessToken)) {
            return response()->json(['status' => 'error', 'error' => 'UNAUTHENTICATED'], 401);
        }

        try {
            $requirements = $supabase->select(
                table: 'booking_requirements',
                filters: ['booking_id' => "eq.{$bookingId}"],
                userAccessToken: $accessToken,
                select: 'id,requirement_key_snapshot,requirement_name_snapshot,document_type_snapshot,is_required,status,created_at,updated_at',
            );
        } catch (SupabaseRpcException $e) {
            return response()->json([
                'status' => 'error',
                'error' => 'REQUIREMENTS_FETCH_FAILED',
                'code' => $e->getMessage(),
            ], 422);
        }

        return response()->json([
            'status' => 'success',
            'data' => $requirements,
        ]);
    }

    public function store(Request $request, SupabaseRpcService $supabase): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'booking_requirement_id' => ['required', 'uuid'],
            'customer_document_id' => ['required', 'uuid'],
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

        // Still need to resolve the caller's own user id via Supabase Auth —
        // Laravel's direct DB connection has no notion of auth.uid(), so
        // this is the one REST call still made here. Same call
        // /account/profile and PaymentSubmissionController already make.
        try {
            $user = $supabase->getCurrentUser($accessToken);
        } catch (SupabaseRpcException $e) {
            return response()->json(['status' => 'error', 'error' => 'UNAUTHENTICATED'], 401);
        }

        $userId = $user['id'] ?? null;

        if (blank($userId)) {
            return response()->json(['status' => 'error', 'error' => 'UNAUTHENTICATED'], 401);
        }

        try {
            $submission = DB::transaction(function () use ($data, $userId) {
                // Lock the requirement row (+ its booking's owner) for the
                // duration of this transaction so two concurrent
                // submissions against the same requirement can't both
                // compute the same attempt_number or both pass the
                // status check.
                $requirement = DB::table('booking_requirements as br')
                    ->join('bookings as b', 'b.id', '=', 'br.booking_id')
                    ->where('br.id', $data['booking_requirement_id'])
                    ->lockForUpdate('br')
                    ->select('br.*', 'b.customer_id')
                    ->first();

                if (!$requirement) {
                    throw new \RuntimeException('REQUIREMENT_NOT_FOUND');
                }

                if ((string) $requirement->customer_id !== (string) $userId) {
                    throw new \RuntimeException('REQUIREMENT_NOT_YOURS');
                }

                // ASSUMPTION (flagged, not confirmed against a spec):
                // allow first-time submission (pending_submission) and
                // resubmission after rejection (rejected). If a rejected
                // requirement should require an admin step first, tighten
                // this list.
                if (!in_array($requirement->status, ['pending_submission', 'rejected'], true)) {
                    throw new \RuntimeException('REQUIREMENT_NOT_SUBMITTABLE:' . $requirement->status);
                }

                $document = DB::table('customer_documents')
                    ->where('id', $data['customer_document_id'])
                    ->first();

                if (!$document) {
                    throw new \RuntimeException('DOCUMENT_NOT_FOUND');
                }

                if ((string) $document->owner_user_id !== (string) $userId) {
                    throw new \RuntimeException('DOCUMENT_NOT_YOURS');
                }

                if ($document->status !== 'active') {
                    throw new \RuntimeException('DOCUMENT_NOT_ACTIVE');
                }

                if ($document->document_type !== $requirement->document_type_snapshot) {
                    throw new \RuntimeException('DOCUMENT_TYPE_MISMATCH:' . $requirement->document_type_snapshot);
                }

                $attemptNumber = (int) (DB::table('booking_requirement_submissions')
                    ->where('booking_requirement_id', $data['booking_requirement_id'])
                    ->max('attempt_number') ?? 0) + 1;

                $submissionId = (string) Str::uuid();

                DB::table('booking_requirement_submissions')->insert([
                    'id' => $submissionId,
                    'booking_requirement_id' => $data['booking_requirement_id'],
                    'customer_document_id' => $data['customer_document_id'],
                    'attempt_number' => $attemptNumber,
                    'review_status' => 'pending',
                    'submitted_at' => now(),
                    'updated_at' => now(),
                ]);

                DB::table('booking_requirements')
                    ->where('id', $data['booking_requirement_id'])
                    ->update([
                        'status' => 'pending_review',
                        'updated_at' => now(),
                    ]);

                return DB::table('booking_requirement_submissions')
                    ->where('id', $submissionId)
                    ->first();
            });
        } catch (\RuntimeException $e) {
            return $this->mapDomainError($e);
        }

        return response()->json([
            'status' => 'created',
            'data' => $submission,
        ], 201);
    }

    private function mapDomainError(\RuntimeException $e): JsonResponse
    {
        $message = $e->getMessage();

        if ($message === 'REQUIREMENT_NOT_FOUND' || $message === 'DOCUMENT_NOT_FOUND') {
            return response()->json([
                'status' => 'error',
                'error' => $message,
            ], 404);
        }

        if ($message === 'REQUIREMENT_NOT_YOURS' || $message === 'DOCUMENT_NOT_YOURS') {
            return response()->json([
                'status' => 'error',
                'error' => 'FORBIDDEN',
                'message' => 'This requirement or document does not belong to you.',
            ], 403);
        }

        if (str_starts_with($message, 'REQUIREMENT_NOT_SUBMITTABLE:')) {
            $currentStatus = substr($message, strlen('REQUIREMENT_NOT_SUBMITTABLE:'));

            return response()->json([
                'status' => 'error',
                'error' => 'REQUIREMENT_NOT_SUBMITTABLE',
                'message' => 'This requirement cannot accept a new submission right now.',
                'current_status' => $currentStatus,
            ], 409);
        }

        if ($message === 'DOCUMENT_NOT_ACTIVE') {
            return response()->json([
                'status' => 'error',
                'error' => 'DOCUMENT_NOT_ACTIVE',
                'message' => 'This document is no longer active. Please upload a new one.',
            ], 409);
        }

        if (str_starts_with($message, 'DOCUMENT_TYPE_MISMATCH:')) {
            $expectedType = substr($message, strlen('DOCUMENT_TYPE_MISMATCH:'));

            return response()->json([
                'status' => 'error',
                'error' => 'DOCUMENT_TYPE_MISMATCH',
                'message' => 'This document does not match what this requirement expects.',
                'expected_document_type' => $expectedType,
            ], 422);
        }

        report($e);

        return response()->json([
            'status' => 'error',
            'error' => 'REQUIREMENT_SUBMISSION_FAILED',
            'code' => $message,
        ], 500);
    }
}