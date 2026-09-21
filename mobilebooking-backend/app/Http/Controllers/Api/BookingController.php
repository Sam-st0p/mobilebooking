<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\Supabase\SupabaseRpcException;
use App\Services\Supabase\SupabaseRpcService;
use App\Support\BookingStatusDeriver;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use Illuminate\Support\Facades\Validator;

/**
 * IMPORTANT SCHEMA NOTE (found while fixing this contract):
 *
 * `bookings` carries a set of legacy single-item columns from an earlier
 * schema iteration — fulfillment_method, daily_rate, rental_subtotal,
 * total_amount, delivery_fee, location, rental_days, product_id,
 * inventory_unit_id, user_id, product_snapshot, customer_snapshot — none
 * of which `create_time_based_booking()` / `create_multi_day_time_based_booking()`
 * actually write. They sit at column defaults ('{}'::jsonb, 0, null)
 * forever. The REAL data lives on `booking_items` (pricing, product name)
 * and `booking_fulfillments` (method, address, fees). This controller
 * reads from those, never from the legacy columns on `bookings` itself.
 *
 * Because of that, `product_snapshot`/`customer_snapshot` passed into the
 * RPC are NOT persisted anywhere queryable — the only place
 * customer_snapshot's contents matter is that create_time_based_booking()
 * copies `fullName`/`phone` out of it into booking_fulfillments at
 * creation time. So it still has to be built correctly, even though it's
 * never read back as a blob.
 *
 * `specialDiscountAmount` (p_discount_amount) is accepted by the RPC but
 * never stored anywhere either — there is currently no way to read it
 * back after creation. Flutter's createBooking() doesn't send a discount
 * today, so this isn't blocking, but flagging it: if discounts are ever
 * sent from the client, they'll silently vanish after the initial
 * response unless a column is added to persist them.
 *
 * FIXED (this pass): `requirements_status` / `agreement_status` were
 * being read directly off `bookings`, same as the other legacy columns
 * above — they are also stale/default values, not the truth. Confirmed
 * against bookingService.ts / types/booking.ts: both are now derived
 * from booking_requirements / booking_agreements child rows on every
 * read. See App\Support\BookingStatusDeriver.
 */
class BookingController extends Controller
{
    private const PICKUP_LOCATION_LABEL = 'Pickup — Right Focus Off Campus, Manuel Hizon, Sta. Cruz, Manila';

    /**
     * Sent as p_variant for products that have NO colors/variants.
     *
     * create_multi_day_time_based_booking() derives its internal variant with
     * regexp_split_to_table(coalesce(specifications->>'colors',''), ','), and
     * splitting '' yields ONE empty-string row, which "matches" a NULL/empty
     * p_variant. The variant then becomes '' (not NULL), and no unit — whose
     * variant is NULL — can match it, so the function raises
     * NO_VARIANT_AVAILABILITY:<product id>: (empty tail). Any NON-EMPTY value
     * that matches no color leaves the variant NULL, which matches every unit.
     * Fix properly in Supabase (nullif(trim(value), '')) when the database can
     * be changed; until then this value works around it.
     */
    private const NO_VARIANT_PLACEHOLDER = '__none__';

    public function store(Request $request, SupabaseRpcService $supabase): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'productId' => ['required', 'uuid'],
            'quantity' => ['nullable', 'integer', 'min:1', 'max:10'],
            'variant' => ['nullable', 'string', 'max:120'],
            'pickupAt' => ['required', 'date'],
            'rentalDays' => ['nullable', 'integer', 'min:1', 'max:30'],
            'fulfillmentMethod' => ['required', 'string', 'in:pickup,delivery'],
            'location' => ['nullable', 'string'],
            'cityMunicipality' => ['nullable', 'string'],
            'province' => ['nullable', 'string'],
            'customerNotes' => ['nullable', 'string'],
            // Rental Details (Step 1) — confirmed required against
            // src/services/bookingSubmissionService.ts::validateReservationDetails.
            // These come fresh from what the customer types on that step;
            // they are NOT pulled from the stored profile row (that was
            // this method's bug before this fix).
            'customerFullName' => ['required', 'string', 'max:200'],
            'customerEmail' => ['required', 'email', 'max:254'],
            'customerPhone' => ['required', 'string', 'regex:/^\d{11}$/'],
            'customerStreetBarangay' => ['required', 'string', 'max:240'],
            'customerCityMunicipality' => ['required', 'string', 'max:120'],
            'customerProvince' => ['required', 'string', 'max:120'],
            'customerFacebookLink' => ['required', 'string', 'max:500'],
            'customerInstagramLink' => ['required', 'string', 'max:500'],
        ]);

        if ($validator->fails()) {
            return response()->json([
                'error' => $validator->errors()->first(),
            ], 422);
        }

        $data = $validator->validated();

        $accessToken = $request->attributes->get('supabase_access_token')
            ?? $request->bearerToken();

        if (blank($accessToken)) {
            return response()->json(['error' => 'You need to be signed in to book.'], 401);
        }

        try {
            $authUser = $supabase->getCurrentUser($accessToken);
        } catch (SupabaseRpcException $e) {
            return response()->json(['error' => 'Your session has expired. Please sign in again.'], 401);
        }

        $userId = $authUser['id'] ?? null;
        if (blank($userId)) {
            return response()->json(['error' => 'Could not resolve your account. Please sign in again.'], 401);
        }

        // Server-built product snapshot — never trust client-sent pricing.
        // Read straight off Laravel's own Postgres connection (already
        // established as safe for direct reads in the Step 4 work).
        $product = DB::table('products')->where('id', $data['productId'])->first();
        if (!$product) {
            return response()->json(['error' => 'This item is no longer available.'], 404);
        }

        // Read defensively, the same way the /catalog route's mapProduct() does:
        // reading a column that doesn't exist on this products table is an
        // "Undefined property" ErrorException, i.e. an HTML 500 page.
        $productSnapshot = [
            'name' => (string) ($product->name ?? ''),
            'brand' => (string) ($product->brand ?? ''),
            'category' => (string) ($product->category ?? ''),
            'dailyRate' => (float) ($product->daily_rate ?? $product->price ?? 0),
            'refundableDeposit' => (float) ($product->refundable_deposit ?? 0),
        ];

        // Products with colors need one of them chosen; products without any
        // must send the placeholder above (see NO_VARIANT_PLACEHOLDER).
        $specs = is_string($product->specifications ?? null)
            ? (json_decode($product->specifications, true) ?? [])
            : (array) ($product->specifications ?? []);
        $colors = array_values(array_filter(array_map('trim', explode(',', (string) ($specs['colors'] ?? '')))));
        $variant = trim((string) ($data['variant'] ?? ''));

        if ($colors !== []) {
            $known = array_map('mb_strtolower', $colors);
            if ($variant === '' || !in_array(mb_strtolower($variant), $known, true)) {
                return response()->json([
                    'error' => 'Please choose an option for this item: ' . implode(', ', $colors) . '.',
                ], 422);
            }
        } else {
            $variant = self::NO_VARIANT_PLACEHOLDER;
        }

        // Fresh from what the customer typed on Rental Details (Step 1) —
        // confirmed against reservationDraft.ts::formatCustomerAddress and
        // bookingSubmissionService.ts's customerSnapshot construction.
        // Deliberately NOT read from the stored profile row: the real
        // flow lets the customer confirm/update these per booking rather
        // than silently reusing whatever's on file.
        $customerAddress = trim(implode(', ', array_filter([
            trim($data['customerStreetBarangay']),
            trim($data['customerCityMunicipality']),
            trim($data['customerProvince']),
        ], fn ($part) => $part !== '')));

        $customerSnapshot = [
            'fullName' => trim($data['customerFullName']),
            'email' => trim($data['customerEmail']),
            'phone' => trim($data['customerPhone']),
            'address' => $customerAddress,
            'facebookLink' => trim($data['customerFacebookLink']),
            'instagramLink' => trim($data['customerInstagramLink']),
        ];

        try {
            $bookingRow = $supabase->call(
                functionName: 'create_multi_day_time_based_booking',
                params: [
                    'p_product_id' => $data['productId'],
                    'p_pickup_at' => $data['pickupAt'],
                    'p_fulfillment_method' => $data['fulfillmentMethod'],
                    'p_location' => $data['location'] ?? null,
                    'p_customer_notes' => $data['customerNotes'] ?? null,
                    'p_delivery_fee' => 0,
                    'p_discount_amount' => 0,
                    'p_product_snapshot' => $productSnapshot,
                    'p_customer_snapshot' => $customerSnapshot,
                    'p_emergency_contact' => null,
                    'p_city_municipality' => $data['cityMunicipality'] ?? null,
                    'p_province' => $data['province'] ?? null,
                    'p_quantity' => $data['quantity'] ?? 1,
                    'p_rental_days' => $data['rentalDays'] ?? 1,
                    // The database has TWO overloads of this function: with and
                    // without a trailing `p_variant text`. Omitting it made both
                    // match and PostgREST refused to choose (PGRST203). Naming
                    // p_variant selects the 15-parameter version unambiguously.
                    'p_variant' => $variant,
                ],
                userAccessToken: $accessToken,
            );
        } catch (SupabaseRpcException $e) {
            return $this->mapRpcError($e);
        }

        $bookingId = $this->extractBookingId($bookingRow);

        if (blank($bookingId)) {
            report(new \RuntimeException('Booking RPC returned no id. Response: ' . json_encode($bookingRow)));

            return response()->json(['error' => 'Something went wrong creating your booking. Please try again.'], 500);
        }

        $booking = $this->fetchBookingForResponse($bookingId);
        if (!$booking) {
            report(new \RuntimeException("Booking {$bookingId} was created but could not be read back"));

            return response()->json(['error' => 'Your booking was created, but we could not load its details. Please check your bookings list.'], 500);
        }

        return response()->json(['booking' => $booking], 201);
    }

    public function index(Request $request): JsonResponse
    {
        $userId = $this->resolveUserId($request);
        if (blank($userId)) {
            return response()->json(['error' => 'You need to be signed in to view your bookings.'], 401);
        }

        $bookingIds = DB::table('bookings')
            ->where('customer_id', $userId)
            ->orderByDesc('created_at')
            ->pluck('id');

        $bookings = $bookingIds
            ->map(function ($id) {
                try {
                    return $this->fetchBookingForResponse($id);
                } catch (\Throwable $e) {
                    // One unreadable booking must not hide the customer's other bookings.
                    report($e);

                    return null;
                }
            })
            ->filter()
            ->values();

        return response()->json(['bookings' => $bookings]);
    }

    public function show(Request $request, string $id): JsonResponse
    {
        $userId = $this->resolveUserId($request);
        if (blank($userId)) {
            return response()->json(['error' => 'You need to be signed in to view this booking.'], 401);
        }

        $owns = DB::table('bookings')->where('id', $id)->where('customer_id', $userId)->exists();
        if (!$owns) {
            return response()->json(['error' => 'Booking not found.'], 404);
        }

        $booking = $this->fetchBookingForResponse($id);
        if (!$booking) {
            return response()->json(['error' => 'Booking not found.'], 404);
        }

        return response()->json(['booking' => $booking]);
    }

    /**
     * Finds the new booking's uuid in whatever shape the RPC replied with:
     *   {"id": "..."}            a bookings row (what this code originally assumed)
     *   {"booking_id": "..."}    a function that RETURNS TABLE(booking_id ...)
     *   {"booking": {...}}       a jsonb wrapper (also "data" / "result")
     *   {"<function_name>": ..}  PostgREST's wrapper for scalar results
     */
    private function extractBookingId(array $row, int $depth = 0): ?string
    {
        foreach (['id', 'booking_id', 'bookingId'] as $key) {
            $value = $row[$key] ?? null;
            if (is_string($value) && Str::isUuid($value)) {
                return $value;
            }
        }

        if ($depth >= 2) {
            return null;
        }

        foreach (['booking', 'data', 'result', 'create_multi_day_time_based_booking'] as $wrapper) {
            $inner = $row[$wrapper] ?? null;

            if (is_string($inner) && Str::isUuid($inner)) {
                return $inner;
            }
            if (is_array($inner)) {
                $found = $this->extractBookingId($inner, $depth + 1);
                if ($found !== null) {
                    return $found;
                }
            }
        }

        return null;
    }

    /**
     * The read-back query selects the WHOLE product row as JSON (to_jsonb(p)) instead
     * of naming columns, so it keeps working whatever columns `products` has — naming
     * p.brand / p.category threw "column does not exist" on this database.
     *
     * @return array{brand:string, category:string, specifications:array}
     */
    private function decodeProductRow(?string $json): array
    {
        $row = $json ? (json_decode($json, true) ?: []) : [];

        $specs = $row['specifications'] ?? [];
        if (is_string($specs)) {
            $specs = json_decode($specs, true) ?: [];
        }

        return [
            'brand' => (string) ($row['brand'] ?? ''),
            'category' => (string) ($row['category'] ?? ''),
            'specifications' => is_array($specs) ? $specs : [],
        ];
    }

    private function resolveUserId(Request $request): ?string
    {
        // Same trust boundary as store(): whatever middleware verified the
        // bearer JWT is expected to have attached the resolved user id.
        // Falling back to decoding the token here would duplicate that
        // verification logic, so this assumes the attribute is set.
        return $request->attributes->get('supabase_user_id');
    }

    /**
     * Reads the AUTHORITATIVE booking data — booking_items and
     * booking_fulfillments — rather than the unused legacy columns
     * sitting on `bookings` itself. See class-level note.
     */
    private function fetchBookingForResponse(string $bookingId): ?array
    {
        $b = DB::selectOne('
            SELECT
                b.id,
                b.booking_reference,
                b.customer_id,
                b.is_guest_checkout,
                b.status,
                lower(b.rental_period) AS period_start,
                upper(b.rental_period) AS period_end,
                (upper(b.rental_period) - lower(b.rental_period)) AS day_count,
                b.pickup_at,
                b.return_at,
                b.next_available_at,
                b.customer_notes,
                b.admin_notes,
                b.birthday_discount_amount,
                b.birthday_discount_status,
                b.loyalty_completed_rentals_snapshot,
                b.loyalty_discount_amount,
                b.loyalty_discount_status,
                b.balance_payment_preference,
                b.pay_later_allowed,
                b.approved_at,
                b.confirmed_at,
                b.rejected_at,
                b.ready_for_release_at,
                b.released_at,
                b.returned_at,
                b.cancelled_at,
                b.created_at,
                b.updated_at,
                bf.method AS fulfillment_method,
                bf.address_line_1,
                bf.city_municipality,
                bf.province,
                COALESCE(bf.delivery_fee_snapshot, 0) AS delivery_fee,
                bf.pickup_convenience_fee_snapshot
            FROM bookings b
            LEFT JOIN booking_fulfillments bf ON bf.booking_id = b.id
            WHERE b.id = ?
        ', [$bookingId]);

        if (!$b) {
            return null;
        }

        $items = DB::select('
            SELECT
                bi.id AS booking_item_id,
                bi.product_id,
                bi.product_name_snapshot,
                bi.daily_rate_snapshot,
                bi.deposit_per_unit_snapshot,
                bi.quantity,
                to_jsonb(p) AS product_row,
                COALESCE(ur.unit_count, 0) AS assigned_unit_count
            FROM booking_items bi
            LEFT JOIN products p ON p.id = bi.product_id
            LEFT JOIN (
                SELECT booking_item_id, COUNT(*) AS unit_count
                FROM unit_reservations
                WHERE status IN (\'tentative\', \'confirmed\', \'in_use\')
                GROUP BY booking_item_id
            ) ur ON ur.booking_item_id = bi.id
            WHERE bi.booking_id = ?
            ORDER BY bi.created_at
        ', [$bookingId]);

        $dayCount = (int) ($b->day_count ?? 1);
        $mappedItems = [];
        $rentalSubtotal = 0.0;
        $refundableDeposit = 0.0;

        foreach ($items as $item) {
            $product = $this->decodeProductRow($item->product_row ?? null);
            $specs = $product['specifications'];
            $dailyRate = (float) $item->daily_rate_snapshot;
            $quantity = (int) $item->quantity;
            $lineTotal = $dailyRate * $quantity * max($dayCount, 1);

            $rentalSubtotal += $lineTotal;
            $refundableDeposit += (float) $item->deposit_per_unit_snapshot * $quantity;

            $included = [];
            if (!empty($specs['included']) && is_string($specs['included'])) {
                $included = array_values(array_filter(array_map('trim', explode(',', $specs['included']))));
            }

            $mappedItems[] = [
                'bookingItemId' => $item->booking_item_id,
                'productId' => $item->product_id,
                'productName' => $item->product_name_snapshot,
                'brand' => $product['brand'],
                'category' => $product['category'],
                'image' => $specs['image'] ?? '',
                'quantity' => $quantity,
                'dailyRate' => $dailyRate,
                'refundableDeposit' => (float) $item->deposit_per_unit_snapshot,
                'included' => $included,
                'lineRentalSubtotal' => $lineTotal,
                'assignedUnitCount' => (int) $item->assigned_unit_count,
            ];
        }

        $primary = $items[0] ?? null;
        $primaryProduct = $this->decodeProductRow($primary->product_row ?? null);
        $primarySpecs = $primaryProduct['specifications'];
        $primaryIncluded = [];
        if (!empty($primarySpecs['included']) && is_string($primarySpecs['included'])) {
            $primaryIncluded = array_values(array_filter(array_map('trim', explode(',', $primarySpecs['included']))));
        }

        $fulfillmentMethod = $b->fulfillment_method ?? 'pickup';
        $location = $fulfillmentMethod === 'pickup'
            ? self::PICKUP_LOCATION_LABEL
            : implode(', ', array_filter([$b->address_line_1, $b->city_municipality, $b->province]));

        $deliveryFee = (float) $b->delivery_fee;
        $pickupConvenienceFee = $b->pickup_convenience_fee_snapshot !== null
            ? (float) $b->pickup_convenience_fee_snapshot
            : null;

        $totalAmount = $rentalSubtotal
            + $deliveryFee
            + ($pickupConvenienceFee ?? 0)
            - (float) $b->birthday_discount_amount
            - (float) $b->loyalty_discount_amount;

        return [
            'id' => $b->id,
            'bookingRef' => $b->booking_reference,
            'customerId' => $b->customer_id,
            'isGuestCheckout' => (bool) $b->is_guest_checkout,
            'items' => $mappedItems,
            'quantity' => array_sum(array_column($mappedItems, 'quantity')) ?: 1,
            'status' => $b->status,
            'fulfillmentMethod' => $fulfillmentMethod,
            'startDate' => $this->isoOrNull($b->pickup_at),
            'endDate' => $this->isoOrNull($b->return_at),
            'nextAvailableAt' => $this->isoOrNull($b->next_available_at),
            'dayCount' => $dayCount,
            'dailyRate' => $primary ? (float) $primary->daily_rate_snapshot : 0,
            'refundableDeposit' => $refundableDeposit,
            'rentalSubtotal' => $rentalSubtotal,
            // See class-level note: p_discount_amount is never persisted,
            // so this can't be reconstructed after creation yet.
            'specialDiscountAmount' => 0,
            'birthdayDiscountAmount' => (float) $b->birthday_discount_amount,
            'birthdayDiscountStatus' => $b->birthday_discount_status,
            'loyaltyCompletedRentalsSnapshot' => (int) $b->loyalty_completed_rentals_snapshot,
            'loyaltyDiscountAmount' => (float) $b->loyalty_discount_amount,
            'loyaltyDiscountStatus' => $b->loyalty_discount_status,
            'deliveryFee' => $deliveryFee,
            'pickupConvenienceFee' => $pickupConvenienceFee,
            'totalAmount' => $totalAmount,
            'balancePaymentPreference' => $b->balance_payment_preference,
            'payLaterAllowed' => (bool) $b->pay_later_allowed,
            'location' => $location,
            'customerNotes' => $b->customer_notes,
            'adminNotes' => $b->admin_notes,
            'productSnapshot' => [
                'name' => $primary->product_name_snapshot ?? 'Item',
                'brand' => $primaryProduct['brand'],
                'category' => $primaryProduct['category'],
                'image' => $primarySpecs['image'] ?? '',
                'pricePerDay' => $primary ? (float) $primary->daily_rate_snapshot : 0,
                'currency' => 'PHP',
                'included' => $primaryIncluded,
                'color' => $primarySpecs['color'] ?? null,
            ],
            // FIXED: derived from child rows, not read off stale/legacy
            // bookings.requirements_status / bookings.agreement_status
            // columns. See App\Support\BookingStatusDeriver.
            'requirementsStatus' => BookingStatusDeriver::requirementsStatus($bookingId),
            'agreementStatus' => BookingStatusDeriver::agreementStatus($bookingId),
            'approvedAt' => $this->isoOrNull($b->approved_at),
            'confirmedAt' => $this->isoOrNull($b->confirmed_at),
            'rejectedAt' => $this->isoOrNull($b->rejected_at),
            'readyForReleaseAt' => $this->isoOrNull($b->ready_for_release_at),
            'releasedAt' => $this->isoOrNull($b->released_at),
            'returnedAt' => $this->isoOrNull($b->returned_at),
            'cancelledAt' => $this->isoOrNull($b->cancelled_at),
            'createdAt' => $this->isoOrNull($b->created_at),
            'updatedAt' => $this->isoOrNull($b->updated_at),
        ];
    }

    private function isoOrNull(?string $value): ?string
    {
        if (blank($value)) {
            return null;
        }

        // Postgres timestamptz comes back from a raw query as a string
        // already in a Carbon-parseable format; re-emit as strict ISO8601
        // so DateTime.parse() on the Flutter side never trips on offset
        // formatting differences.
        return \Carbon\Carbon::parse($value)->toIso8601String();
    }

    private function mapRpcError(SupabaseRpcException $e): JsonResponse
    {
        $message = $e->getMessage();

        if ($message === 'INVALID_RENTAL_DAYS') {
            return response()->json(['error' => 'Rental duration must be between 1 and 30 days.'], 422);
        }

        if ($message === 'PRODUCT_NOT_AVAILABLE') {
            return response()->json(['error' => 'This item is no longer available.'], 404);
        }

        if ($message === 'DELIVERY_ADDRESS_REQUIRED') {
            return response()->json(['error' => 'A delivery address is required for delivery bookings.'], 422);
        }

        if ($message === 'PICKUP_TIME_IN_PAST' || $message === 'PICKUP_TIME_REQUIRED') {
            return response()->json(['error' => 'Please choose a valid pickup time.'], 422);
        }

        if ($message === 'CUSTOMER_PROFILE_REQUIRED') {
            return response()->json(['error' => 'Please complete your profile before booking.'], 422);
        }

        if ($message === 'ACCOUNT_SUSPENDED') {
            return response()->json(['error' => 'Your account is suspended. Please contact support.'], 403);
        }

        if (str_starts_with($message, 'NO_TIME_AVAILABILITY:')) {
            $suggestedNextPickupAt = substr($message, strlen('NO_TIME_AVAILABILITY:'));

            return response()->json([
                'error' => 'Not enough units are available for the full requested period.',
                'suggestedNextPickupAt' => $suggestedNextPickupAt,
            ], 409);
        }

        if ($message === 'VARIANT_NOT_AVAILABLE') {
            return response()->json(['error' => 'That option is not available. Please choose another one.'], 422);
        }

        if (str_starts_with($message, 'NO_VARIANT_AVAILABILITY:')) {
            return response()->json([
                'error' => 'Not enough units of that option are available for the requested dates.',
            ], 409);
        }

        if ($message === 'BOOKING_ITEM_REQUIRED') {
            report($e);

            return response()->json(['error' => 'Something went wrong creating your booking. Please try again.'], 500);
        }

        report($e);

        // In local/debug mode, put the database's real message in the response so it
        // shows up right in the app (and the browser's Network tab) — no digging
        // through logs. Never exposed when APP_DEBUG is false.
        $error = 'Could not create your booking. Please try again.';
        if (config('app.debug')) {
            $error .= ' [debug: ' . $e->getMessage()
                . ($e->pgCode !== null ? ' | code ' . $e->pgCode : '')
                . ' | http ' . $e->httpStatus . ']';
        }

        return response()->json(['error' => $error], 422);
    }
}