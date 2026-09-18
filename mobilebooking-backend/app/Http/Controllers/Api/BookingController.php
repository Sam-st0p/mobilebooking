<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Booking;
use Illuminate\Http\Request;

class BookingController extends Controller
{
    public function index()
    {
        return response()->json([
            'status' => 'success',
            'data' => Booking::all()
        ]);
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'booking_reference' => 'required|string',
            'status' => 'required|string',
        ]);

        $booking = Booking::create($validated);

        return response()->json([
            'status' => 'created',
            'data' => $booking
        ], 201);
    }
}
