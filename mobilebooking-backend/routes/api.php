<?php

use App\Http\Controllers\Api\BookingController;
use App\Http\Controllers\Api\BookingDocumentController;
use App\Http\Controllers\Api\NotificationController;
use App\Http\Controllers\Api\PaymentSubmissionController;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Route;

// Builds a public Supabase Storage URL from a bucket + path, the same way
// ProfileController::photoUrl() does for avatars. Assumes the bucket is
// PUBLIC (the website already renders these without a signed URL, so this
// should hold) — if photos ever stop loading, that's the first thing to check.
$supabasePublicUrl = function (string $bucket, string $path) {
    return rtrim((string) config('services.supabase.url'), '/')
        . '/storage/v1/object/public/' . $bucket . '/' . ltrim($path, '/');
};

$mapProduct = function ($p, $imageRows = []) use ($supabasePublicUrl) {
    // Fetch real data directly from DB columns
    $specs = is_string($p->specifications ?? '')
        ? (json_decode($p->specifications, true) ?? [])
        : (array) ($p->specifications ?? []);

    // Real product photos live in the `product_images` table (one row per
    // photo, with `storage_bucket` + `storage_path` and a `sort_order`) — NOT
    // in `specifications`, which is always empty for these. This is exactly
    // what the website's gallery reads. [$id => rows] is passed in by the
    // caller so the catalog list only needs one extra query total, not one
    // per product. Products with no rows there yet fall back to a single
    // placeholder image so nothing breaks for them.
    $imageRows = is_array($imageRows) ? $imageRows : (is_iterable($imageRows) ? iterator_to_array($imageRows) : []);
    if ($imageRows !== []) {
        usort($imageRows, fn ($a, $b) => ($a->sort_order ?? 0) <=> ($b->sort_order ?? 0));
        $images = array_values(array_map(fn ($row) => [
            'id' => (string) $row->id,
            'url' => $supabasePublicUrl((string) $row->storage_bucket, (string) $row->storage_path),
            'isPrimary' => (bool) $row->is_primary,
        ], $imageRows));
    } else {
        // Old fallback, kept for any product that has no product_images rows yet.
        $imageUrl = $p->image_url ?? $p->image ?? '';
        if (empty($imageUrl) && isset($specs['images']) && is_array($specs['images'])) {
            $imageUrl = $specs['images'][0]['url'] ?? $specs['images'][0] ?? '';
        }
        $images = [[
            'id' => 'img_' . $p->id,
            'url' => (string) $imageUrl,
            'isPrimary' => true,
        ]];
    }

    return [
        'id' => (string) $p->id,
        'slug' => (string) ($p->slug ?? $p->id),
        'name' => (string) $p->name,
        'brand' => (string) ($p->brand ?? ''),
        'category' => (string) ($p->category ?? ''),
        'shortDescription' => (string) ($p->short_description ?? ''),
        'description' => (string) ($p->description ?? ''),
        'dailyRate' => (float) ($p->daily_rate ?? $p->price ?? 0),
        'refundableDeposit' => (float) ($p->refundable_deposit ?? 0),
        'currency' => 'PHP',
        'status' => (string) ($p->status ?? 'active'),
        'isFeatured' => (bool) ($p->is_featured ?? false),
        'specifications' => $specs,
        'images' => $images,
        'totalUnits' => (int) ($p->total_units ?? $p->quantity ?? 1),
        'availableUnits' => (int) ($p->available_units ?? $p->total_units ?? $p->quantity ?? 1),
        'rating' => (float) ($p->rating ?? 5.0),
        'reviewCount' => (int) ($p->review_count ?? 0),
        'createdAt' => (string) ($p->created_at ?? now()),
        'updatedAt' => (string) ($p->updated_at ?? now()),
    ];
};

$registerMobileRoutes = function ($prefix) use ($mapProduct) {
    Route::group(['prefix' => $prefix], function () use ($mapProduct) {

        // Full Catalog Route
        Route::get('/catalog', function () use ($mapProduct) {
            $products = DB::table('products')->get();

            // One extra query for ALL products' photos, grouped in PHP — avoids
            // running a separate product_images query per product (N+1).
            $imagesByProduct = DB::table('product_images')
                ->whereIn('product_id', $products->pluck('id'))
                ->orderBy('sort_order')
                ->get()
                ->groupBy('product_id');

            $mapped = $products->map(
                fn ($p) => $mapProduct($p, $imagesByProduct->get($p->id, collect())->all())
            );

            return response()->json(['success' => true, 'products' => $mapped]);
        });

        // Single Product Route
        Route::get('/catalog/{id}', function ($id) use ($mapProduct) {
            $p = DB::table('products')->where('id', $id)->first();
            if (!$p) return response()->json(['success' => false, 'message' => 'Not found'], 404);

            $imageRows = DB::table('product_images')
                ->where('product_id', $id)
                ->orderBy('sort_order')
                ->get()
                ->all();

            return response()->json(['success' => true, 'product' => $mapProduct($p, $imageRows)]);
        });

        /*
        |----------------------------------------------------------------
        | Availability Check — REAL, via get_product_availability()
        |----------------------------------------------------------------
        | Confirmed signature: (product_id uuid, start_date date, end_date date)
        | "Whole-range" semantics: a unit only counts as available if it's
        | free for the ENTIRE requested span, not just on one day within it.
        |
        | If no start_date/end_date is passed (e.g. product page loads
        | before the customer picks dates), falls back to checking today
        | only, and still returns a 90-day blockedDates calendar so the
        | frontend's date picker can gray out unavailable days up front.
        */
        Route::any('/catalog/{id}/availability-check', function (Request $request, $id) {
            $quantity = max(1, (int) ($request->input('quantity') ?? 1));
            $startDateInput = $request->input('start_date') ?? $request->input('startDate');
            $endDateInput = $request->input('end_date') ?? $request->input('endDate');

            $wholeRangeStart = $startDateInput ? Carbon::parse($startDateInput) : Carbon::today();
            $wholeRangeEnd = $endDateInput ? Carbon::parse($endDateInput) : $wholeRangeStart->copy();

            // Calendar always covers a fixed 90-day horizon from the range
            // start, regardless of how long the requested stay is, so the
            // picker has enough blocked/open days to render.
            $calendarStart = $wholeRangeStart->copy();
            $calendarEnd = $calendarStart->copy()->addDays(89);

            try {
                $summaryRows = DB::select(
                    'select * from get_product_availability(?, ?, ?)',
                    [$id, $wholeRangeStart->toDateString(), $wholeRangeEnd->toDateString()]
                );

                $calendarRows = DB::select(
                    'select * from get_product_availability_calendar(?, ?, ?)',
                    [$id, $calendarStart->toDateString(), $calendarEnd->toDateString()]
                );
            } catch (\Throwable $e) {
                report($e);

                return response()->json([
                    'success' => false,
                    'message' => 'Availability check is temporarily unavailable.',
                ], 500);
            }

            if (empty($summaryRows)) {
                return response()->json(['success' => false, 'message' => 'Not found'], 404);
            }

            $summary = $summaryRows[0];

            $blockedDates = collect($calendarRows)
                ->filter(fn ($row) => (int) $row->available_units < $quantity)
                ->pluck('day')
                ->values();

            return response()->json([
                'success' => true,
                'isAvailable' => (int) $summary->available_units >= $quantity,
                'availableUnits' => (int) $summary->available_units,
                'totalUnits' => (int) $summary->total_units,
                'blockedDates' => $blockedDates,
            ]);
        });

        /*
        |----------------------------------------------------------------
        | Availability Calendar (new) — via get_product_availability_calendar()
        |----------------------------------------------------------------
        | Per-day breakdown for a given range, for a full calendar-view UI
        | rather than just a blocked/open list.
        */
        Route::get('/catalog/{id}/availability-calendar', function (Request $request, $id) {
            $request->validate([
                'start_date' => ['required', 'date'],
                'end_date' => ['required', 'date', 'after_or_equal:start_date'],
            ]);

            try {
                $rows = DB::select(
                    'select * from get_product_availability_calendar(?, ?, ?)',
                    [$id, $request->input('start_date'), $request->input('end_date')]
                );
            } catch (\Throwable $e) {
                report($e);

                return response()->json([
                    'success' => false,
                    'message' => 'Availability calendar is temporarily unavailable.',
                ], 500);
            }

            return response()->json([
                'success' => true,
                'days' => array_map(fn ($row) => [
                    'date' => $row->day,
                    'totalUnits' => (int) $row->total_units,
                    'availableUnits' => (int) $row->available_units,
                    'confirmedUnavailableUnits' => (int) $row->confirmed_unavailable_units,
                ], $rows),
            ]);
        });

        /*
        |----------------------------------------------------------------
        | Account Profile — REAL, via Supabase
        |----------------------------------------------------------------
        | Forwards the caller's own bearer token to Supabase's
        | /auth/v1/user, so the profile returned is whoever Supabase's own
        | JWT verification says it is. Laravel never verifies the JWT
        | signature itself here.
        */
        Route::get('/account/profile', function (Request $request) {
            $token = $request->bearerToken();

            if (blank($token)) {
                return response()->json(['success' => false, 'message' => 'Unauthenticated.'], 401);
            }

            $response = Http::withHeaders([
                'apikey' => config('services.supabase.anon_key'),
                'Authorization' => "Bearer {$token}",
            ])->get(rtrim(config('services.supabase.url'), '/') . '/auth/v1/user');

            if ($response->failed()) {
                return response()->json(['success' => false, 'message' => 'Unauthenticated.'], 401);
            }

            $user = $response->json();

            return response()->json([
                'success' => true,
                'profile' => [
                    'id' => $user['id'] ?? null,
                    'email' => $user['email'] ?? null,
                    // Supabase stores app-specific fields under user_metadata.
                    // Confirm this key matches what your signup form writes.
                    'fullName' => $user['user_metadata']['full_name'] ?? null,
                    'phone' => $user['phone'] ?? '',
                ],
            ]);
        });

        /*
        |----------------------------------------------------------------
        | Account Bookings — now REAL, via BookingController::index()
        |----------------------------------------------------------------
        | Previously a fallback stub returning an empty array. index()
        | itself was already built and correct; it just wasn't wired up.
        */
        Route::get('/account/bookings', [BookingController::class, 'index']);

        /*
        |----------------------------------------------------------------
        | Auth Endpoints — REAL, via Supabase Auth REST API (GoTrue)
        |----------------------------------------------------------------
        | Supabase sends the real OTP and verifies it; Laravel only
        | proxies the request and relays the real session Supabase issues.
        */
        Route::post('/auth/request-otp', function (Request $request) {
            $request->validate([
                'email' => ['required_without:phone', 'nullable', 'email'],
                'phone' => ['required_without:email', 'nullable', 'string'],
            ]);

            $payload = array_filter([
                'email' => $request->input('email'),
                'phone' => $request->input('phone'),
                // Lets a first-time guest get an OTP without a
                // pre-existing account, matching guest-checkout-first.
                'create_user' => true,
            ]);

            $response = Http::withHeaders([
                'apikey' => config('services.supabase.anon_key'),
                'Content-Type' => 'application/json',
            ])->post(rtrim(config('services.supabase.url'), '/') . '/auth/v1/otp', $payload);

            if ($response->failed()) {
                report(new \RuntimeException('Supabase OTP request failed: ' . $response->body()));

                return response()->json([
                    'success' => false,
                    'message' => $response->json('error_description', $response->json('msg', 'Failed to send OTP.')),
                ], $response->status());
            }

            return response()->json([
                'success' => true,
                'message' => 'OTP sent.',
            ]);
        });

        Route::post('/auth/verify-otp', function (Request $request) {
            $request->validate([
                'email' => ['required_without:phone', 'nullable', 'email'],
                'phone' => ['required_without:email', 'nullable', 'string'],
                'token' => ['required', 'string'],
                'type' => ['nullable', 'string', 'in:email,sms'],
            ]);

            $payload = array_filter([
                'email' => $request->input('email'),
                'phone' => $request->input('phone'),
                'token' => $request->input('token'),
                'type' => $request->input('type', $request->filled('phone') ? 'sms' : 'email'),
            ]);

            $response = Http::withHeaders([
                'apikey' => config('services.supabase.anon_key'),
                'Content-Type' => 'application/json',
            ])->post(rtrim(config('services.supabase.url'), '/') . '/auth/v1/verify', $payload);

            if ($response->failed()) {
                return response()->json([
                    'success' => false,
                    'message' => $response->json('error_description', $response->json('msg', 'Invalid or expired code.')),
                ], $response->status());
            }

            $session = $response->json();

            return response()->json([
                'success' => true,
                'accessToken' => $session['access_token'] ?? null,
                'refreshToken' => $session['refresh_token'] ?? null,
                'expiresIn' => $session['expires_in'] ?? null,
                'user' => $session['user'] ?? null,
            ]);
        });

        // New — wasn't in the original file. Lets the app renew a session
        // without forcing the customer through OTP again.
        Route::post('/auth/refresh', function (Request $request) {
            $request->validate(['refreshToken' => ['required', 'string']]);

            $response = Http::withHeaders([
                'apikey' => config('services.supabase.anon_key'),
                'Content-Type' => 'application/json',
            ])->post(
                rtrim(config('services.supabase.url'), '/') . '/auth/v1/token?grant_type=refresh_token',
                ['refresh_token' => $request->input('refreshToken')]
            );

            if ($response->failed()) {
                return response()->json([
                    'success' => false,
                    'message' => 'Session expired. Please sign in again.',
                ], 401);
            }

            $session = $response->json();

            return response()->json([
                'success' => true,
                'accessToken' => $session['access_token'] ?? null,
                'refreshToken' => $session['refresh_token'] ?? null,
                'expiresIn' => $session['expires_in'] ?? null,
            ]);
        });

        /*
        |----------------------------------------------------------------
        | Bookings — REAL, via BookingController -> Supabase RPC
        |----------------------------------------------------------------
        | Creates a real reservation via create_multi_day_time_based_booking,
        | called through the customer's own Supabase session so auth.uid()
        | resolves correctly. See app/Http/Controllers/Api/BookingController.php.
        */
        Route::post('/bookings', [BookingController::class, 'store']);

        /*
        |----------------------------------------------------------------
        | Payment Submission (Step 3 — GCash proof upload)
        |----------------------------------------------------------------
        | Multipart upload: booking_id, stage, declared_amount,
        | payment_method, external_reference, proof (file).
        | See PaymentSubmissionController for the full flow: uploads to
        | Storage, then writes customer_documents + booking_payment_submissions.
        */
        Route::post('/payment-submissions', [PaymentSubmissionController::class, 'store']);

        /*
        |----------------------------------------------------------------
        | Booking Documents + Agreement (Step 4 + customer side of Step 5,
        | combined — confirmed to be ONE flow, not two)
        |----------------------------------------------------------------
        | upload  uploads a single file (idOne/idTwo/selfie/emergencyId/
        |         signature) to Storage, keyed by kind + submissionId.
        |         Mirrors app/api/bookings/[bookingId]/documents/upload/route.ts.
        | submit  finalizes everything at once in a single transaction:
        |         verification documents, the six agreement
        |         acknowledgements, the customer's signature, and the
        |         emergency contact. Mirrors
        |         app/api/bookings/[bookingId]/documents/submit/route.ts.
        | See BookingDocumentController for the full contract and the
        | ownership/payment-submitted/unit-assignment checks that stand
        | in for RLS + the admin-client validation the real route does.
        */
        Route::post('/bookings/{booking}/documents/upload', [BookingDocumentController::class, 'uploadDocument']);
        Route::post('/bookings/{booking}/documents/submit', [BookingDocumentController::class, 'submitDocuments']);

        /*
        |----------------------------------------------------------------
        | Booking Detail / Tracker (Step 6) — REAL, via BookingController
        |----------------------------------------------------------------
        | Nested under /account/bookings to match the path Flutter's
        | existing booking_service.dart already calls (getBookingById,
        | cancelBooking) — NOT /bookings/{id}, which would've been a
        | silent 404 against the already-written client.
        |
        | show() now returns the base booking PLUS everything the Guest
        | Booking Tracker's Overview/Progress/Documents/Updates tabs need
        | (agreement, documents, statusHistory, payments, receipts,
        | review, emergencyContact, cancellationRequest). Mirrors
        | src/services/bookingDetailService.ts::getBookingDetails.
        |
        | cancel() and updateDetails() wrap the two customer-facing RPCs
        | confirmed in src/services/bookingService.ts
        | (request_booking_cancellation, update_own_booking_details).
        | NOTE: cancel()'s real payload is {reason, additionalDetails},
        | NOT {note} — booking_service.dart's cancelBooking() needs
        | updating to match (see chat notes / Flutter changes).
        |
        | NOTE: "guest" (no-account) booking tracking is NOT covered by
        | these routes yet — they require a resolved supabase_user_id,
        | same trust boundary as the rest of this controller. The real
        | app's guest path additionally goes through
        | recover_guest_booking_access first; that hasn't been ported.
        */
        Route::get('/account/bookings/{id}', [BookingController::class, 'show']);
        Route::post('/account/bookings/{id}/cancel', [BookingController::class, 'cancel']);
        Route::post('/account/bookings/{id}/details', [BookingController::class, 'updateDetails']);

        /*
        |----------------------------------------------------------------
        | Notifications (Updates tab) — REAL, via NotificationController
        |----------------------------------------------------------------
        | User-scoped, not booking-scoped. Confirmed against
        | src/services/notificationService.ts. No realtime push here —
        | Flutter should poll, same fallback the web app itself uses.
        */
        Route::get('/notifications', [NotificationController::class, 'index']);
        Route::post('/notifications/{id}/read', [NotificationController::class, 'markRead']);
    });
};

$registerMobileRoutes('mobile');
$registerMobileRoutes('api/mobile');