<?php

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;
use Illuminate\Support\Facades\DB;

$mapProduct = function ($p) {
    // Fetch real data directly from DB columns
    $specs = is_string($p->specifications ?? '') 
        ? (json_decode($p->specifications, true) ?? []) 
        : (array)($p->specifications ?? []);
    
    // Safely extract primary image URL from direct columns or specs JSON
    $imageUrl = $p->image_url ?? $p->image ?? '';
    if (empty($imageUrl) && isset($specs['images']) && is_array($specs['images'])) {
        $imageUrl = $specs['images'][0]['url'] ?? $specs['images'][0] ?? '';
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
        'images' => [
            [
                'id' => 'img_' . $p->id,
                'url' => (string) $imageUrl,
                'isPrimary' => true,
            ]
        ],
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
            $products = DB::table('products')->get()->map(fn($p) => $mapProduct($p));
            return response()->json(['success' => true, 'products' => $products]);
        });

        // Single Product Route
        Route::get('/catalog/{id}', function ($id) use ($mapProduct) {
            $p = DB::table('products')->where('id', $id)->first();
            if (!$p) return response()->json(['success' => false, 'message' => 'Not found'], 404);
            return response()->json(['success' => true, 'product' => $mapProduct($p)]);
        });

        // Availability Check Endpoint (Handles GET & POST)
        Route::any('/catalog/{id}/availability-check', function ($id) {
            $p = DB::table('products')->where('id', $id)->first();
            $available = (int) ($p->available_units ?? $p->total_units ?? 1);
            
            return response()->json([
                'success' => true,
                'isAvailable' => $available > 0,
                'availableUnits' => $available,
                'totalUnits' => (int) ($p->total_units ?? 1),
                'blockedDates' => []
            ]);
        });

        // Account Profile & Bookings Fallbacks
        Route::get('/account/profile', function () {
            return response()->json([
                'success' => true,
                'profile' => [
                    'id' => 'usr_123',
                    'email' => 'galanelajaypee@gmail.com',
                    'fullName' => 'Jaypee Galanela',
                    'phone' => ''
                ]
            ]);
        });

        Route::get('/account/bookings', function () {
            return response()->json(['success' => true, 'bookings' => []]);
        });

        // Auth Endpoints
        Route::post('/auth/request-otp', function (Request $request) {
            return response()->json([
                'success' => true,
                'message' => 'OTP sent successfully. Dev code: 123456',
                'dev_otp' => '123456'
            ]);
        });

        Route::post('/auth/verify-otp', function (Request $request) {
            return response()->json([
                'success' => true,
                'accessToken' => 'mock-jwt-token',
                'refreshToken' => 'mock-jwt-refresh',
                'user' => ['id' => 'usr_123', 'email' => $request->input('email', 'user@example.com')]
            ]);
        });
    });
};

$registerMobileRoutes('mobile');
$registerMobileRoutes('api/mobile');