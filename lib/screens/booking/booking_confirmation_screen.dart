// lib/screens/booking/booking_confirmation_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/booking.dart';
import '../../theme/app_theme.dart';

class BookingConfirmationScreen extends StatelessWidget {
  final Booking booking;
  const BookingConfirmationScreen({super.key, required this.booking});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle_outline, size: 64, color: AppColors.statusGreen),
              const SizedBox(height: 16),
              const Text('Booking request sent!',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                'Booking #${booking.id.substring(0, 8).toUpperCase()} is now Pending Review. '
                "We'll confirm your payment and dates, then update the status in My Bookings.",
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
        ),
      ),
    );
  }
}
