// lib/screens/booking/payment_pending_screen.dart
//
// Rebuilt against the real model. The old version watched
// booking.isPaid via BookingService.watchBooking(), returning a full
// Booking — neither exists anymore:
//   - Payment status now lives in booking_payment_submissions, not a field
//     on `bookings`. Not built yet (stage 5).
//   - BookingService now only exposes watchBookingStatus() (a flat map of
//     the bookings row), since Realtime .stream() can't return the nested
//     items/fulfillment/totals shape anyway.
//
// This screen is currently UNREACHABLE — reserve_screen.dart no longer
// routes here after booking creation (the real workflow requires admin
// approval + requirements + agreement before payment even starts; see
// reserve_screen.dart's header comment). Left in place, rewritten to at
// least compile and be honest about what it can show today, so it doesn't
// block the build if still referenced from app_router.dart. Once stage 5
// (payment rebuild) lands, this becomes the real "waiting for PayMongo"
// screen again, wired up from wherever payment is actually triggered
// (likely the booking detail screen, after requirements + agreement are
// both complete).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/booking.dart';
import '../../services/booking_service.dart';
import '../../theme/app_theme.dart';

class PaymentPendingScreen extends StatefulWidget {
  final Booking booking;
  const PaymentPendingScreen({super.key, required this.booking});

  @override
  State<PaymentPendingScreen> createState() => _PaymentPendingScreenState();
}

class _PaymentPendingScreenState extends State<PaymentPendingScreen> {
  late final Stream<Map<String, dynamic>?> _statusStream;

  @override
  void initState() {
    super.initState();
    _statusStream = BookingService.watchBookingStatus(widget.booking.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<Map<String, dynamic>?>(
          stream: _statusStream,
          builder: (context, snapshot) {
            final statusStr = snapshot.data?['status'] as String?;
            final status = statusStr != null ? bookingStatusFromString(statusStr) : widget.booking.status;
            return _buildWaiting(widget.booking, status);
          },
        ),
      ),
    );
  }

  Widget _buildWaiting(Booking booking, BookingStatus status) {
    final label = bookingStatusLabel(status);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            height: 48,
            width: 48,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 24),
          Text('Status: $label',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'Booking #${booking.id.substring(0, 8).toUpperCase()} will update here '
            'automatically as Maddy & Cassy review it. Payment happens later, once '
            'your booking is approved and requirements/agreement are complete.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.charcoal, height: 1.5),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => context.go('/account/bookings'),
              child: const Text('Check My Bookings'),
            ),
          ),
        ],
      ),
    );
  }
}