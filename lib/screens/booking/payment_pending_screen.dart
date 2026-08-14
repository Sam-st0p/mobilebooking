// lib/screens/booking/payment_pending_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/booking.dart';
import '../../services/booking_service.dart';
import '../../theme/app_theme.dart';

/// Shown right after the customer is sent to PayMongo's hosted checkout.
/// Subscribes to the booking row via Supabase Realtime, so the moment the
/// paymongo-webhook Edge Function flips payment_status to 'paid' — usually
/// within seconds of completing checkout — this screen updates on its own.
/// No polling, no deep link required: the customer just switches back to
/// the app after paying.
class PaymentPendingScreen extends StatefulWidget {
  final Booking booking;
  const PaymentPendingScreen({super.key, required this.booking});

  @override
  State<PaymentPendingScreen> createState() => _PaymentPendingScreenState();
}

class _PaymentPendingScreenState extends State<PaymentPendingScreen> {
  late final Stream<Booking?> _bookingStream;
  bool _reopeningCheckout = false;
  String? _reopenError;

  @override
  void initState() {
    super.initState();
    _bookingStream = BookingService.watchBooking(widget.booking.id);
  }

  Future<void> _reopenCheckout() async {
    setState(() {
      _reopeningCheckout = true;
      _reopenError = null;
    });
    try {
      final checkoutUrl = await BookingService.createPaymongoCheckoutSession(widget.booking.id);
      await launchUrl(Uri.parse(checkoutUrl), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      setState(() => _reopenError = describeBookingError(e));
    } finally {
      if (mounted) setState(() => _reopeningCheckout = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<Booking?>(
          stream: _bookingStream,
          initialData: widget.booking,
          builder: (context, snapshot) {
            final booking = snapshot.data ?? widget.booking;
            return booking.isPaid ? _buildPaid(booking) : _buildWaiting(booking);
          },
        ),
      ),
    );
  }

  Widget _buildWaiting(Booking booking) {
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
          const Text('Waiting for payment…',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'Booking #${booking.id.substring(0, 8).toUpperCase()} will update here '
            'automatically once PayMongo confirms your payment. Complete checkout '
            'in the browser, then come back to this screen.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.charcoal, height: 1.5),
          ),
          const SizedBox(height: 32),
          if (_reopenError != null) ...[
            Text(_reopenError!, style: const TextStyle(color: AppColors.statusRed), textAlign: TextAlign.center),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _reopeningCheckout ? null : _reopenCheckout,
              child: _reopeningCheckout
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Reopen Payment Page'),
            ),
          ),
          const SizedBox(height: 12),
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

  Widget _buildPaid(Booking booking) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_outline, size: 64, color: AppColors.statusGreen),
          const SizedBox(height: 16),
          const Text('Payment confirmed!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'Booking #${booking.id.substring(0, 8).toUpperCase()} is paid and now Pending '
            "Review. We'll confirm your dates and update the status in My Bookings.",
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.charcoal, height: 1.5),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => context.go('/account/bookings'),
              child: const Text('View My Bookings'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => context.go('/catalog'),
              child: const Text('Continue Browsing'),
            ),
          ),
        ],
      ),
    );
  }
}