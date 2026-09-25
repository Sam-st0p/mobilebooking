<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * GET /account/payments — every GCash payment the signed-in customer has
 * ever submitted, newest first, joined with the booking + product it was
 * for so the list is readable on its own (no follow-up request needed).
 *
 * User-scoped via bookings.customer_id, the same trust boundary as
 * BookingController/NotificationController: whatever middleware verified
 * the bearer JWT is expected to have attached supabase_user_id.
 *
 * Was previously a "Coming soon" placeholder screen in Flutter with no
 * backend route at all.
 */
class PaymentHistoryController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $userId = $request->attributes->get('supabase_user_id');
        if (blank($userId)) {
            return response()->json(['success' => false, 'message' => 'Unauthenticated.'], 401);
        }

        $rows = DB::table('booking_payment_submissions as ps')
            ->join('bookings as b', 'b.id', '=', 'ps.booking_id')
            ->leftJoin('booking_items as bi', function ($join) {
                $join->on('bi.booking_id', '=', 'b.id')->whereRaw('bi.id = (
                    select id from booking_items where booking_id = b.id order by created_at, id limit 1
                )');
            })
            ->leftJoin('products as p', 'p.id', '=', 'bi.product_id')
            ->leftJoin('customer_documents as cd', 'cd.id', '=', 'ps.proof_document_id')
            ->where('b.customer_id', $userId)
            ->orderByDesc('ps.created_at')
            ->select([
                'ps.id',
                'ps.booking_id',
                'ps.stage',
                'ps.status',
                'ps.declared_amount',
                'ps.payment_method',
                'ps.external_reference',
                'ps.created_at',
                'b.booking_reference',
                'p.name as product_name',
                'cd.storage_bucket as proof_bucket',
                'cd.storage_path as proof_path',
            ])
            ->get();

        $payments = $rows->map(function ($row) {
            $proofUrl = null;
            if (filled($row->proof_bucket) && filled($row->proof_path)) {
                $proofUrl = rtrim((string) config('services.supabase.url'), '/')
                    . '/storage/v1/object/public/' . $row->proof_bucket . '/' . ltrim((string) $row->proof_path, '/');
            }

            return [
                'id' => (string) $row->id,
                'bookingId' => (string) $row->booking_id,
                'bookingReference' => (string) ($row->booking_reference ?? ''),
                'productName' => (string) ($row->product_name ?? 'Rental'),
                'stage' => (string) $row->stage, // "down_payment" | "full" | "balance", per the schema
                'status' => (string) ($row->status ?? 'submitted'), // submitted | under_review | verified | rejected
                'amount' => (float) $row->declared_amount,
                'paymentMethod' => (string) ($row->payment_method ?? 'gcash'),
                'referenceNumber' => (string) ($row->external_reference ?? ''),
                'proofUrl' => $proofUrl,
                'submittedAt' => (string) $row->created_at,
            ];
        });

        return response()->json(['success' => true, 'payments' => $payments]);
    }
}