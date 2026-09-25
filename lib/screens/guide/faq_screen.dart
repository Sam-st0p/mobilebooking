// lib/screens/guide/faq_screen.dart
//
// Ported from the web app's /faq page. Content is fixed business copy, not
// fetched from any API.

import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/rental_guide_scaffold.dart';

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  static const _items = <(String, String)>[
    (
      'How do I reserve a rental?',
      'Submit a booking request through the catalog with your item, dates, and handover preference. You may '
          'also message @iosrental.maddycassy through Facebook or TikTok for assistance. The team will '
          'confirm availability and guide you through verification.',
    ),
    (
      'What payment methods do you accept?',
      'Payments may be made through GCash or bank transfer. A down payment is required to hold an approved '
          'unit, with the remaining rental balance due before or at pickup.',
    ),
    (
      'Is a security deposit required?',
      'A non-refundable security deposit may apply. Its exact amount is shown on the product page and '
          'included in the final checkout amount before you pay via GCash.',
    ),
    (
      'How does the birthday month discount work?',
      'Add your birth date to the booking details. When any selected rental date falls within your birth '
          'month, ₱100 is deducted from the rental fee. The birth date must match one of the valid IDs '
          'submitted for verification.',
    ),
    (
      'How does the loyalty reward work?',
      'Every returned booking under the same customer account counts as one completed rental. After ten '
          'completed rentals, ₱200 is automatically applied to the next booking — the 11th rental. No loyalty '
          'card is required, and progress is shown under My Bookings.',
    ),
    (
      'Can I extend my rental?',
      'Extensions may be approved when the unit remains available for the requested dates. Contact the team '
          'before your scheduled return so availability and your rental agreement can be updated.',
    ),
    (
      'What happens if I return the item late?',
      "Late returns incur a ₱100 per hour fee. If the delay affects another renter's booking, an additional "
          'full-day charge may apply. Notify the team immediately when a delay is expected.',
    ),
    (
      'What if the item is damaged or lost?',
      'The renter is responsible for applicable repair costs or replacement value when a unit is damaged, '
          'lost, or returned with missing accessories. Handle every unit with care and report incidents '
          'immediately.',
    ),
    (
      'Are long-term rentals available?',
      'Yes. Contact the team with your dates and requested unit so they can confirm availability and provide '
          'a personalized quote.',
    ),
    (
      'How do I pick up or return the item?',
      'Pickup and return are arranged at Right Focus Off Campus — Manuel Hizon, Sta. Cruz, Manila. Delivery or '
          'pickup may also be arranged through Grab, Lalamove, or Angkas, with roundtrip fees handled by the '
          'renter.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return RentalGuideScaffold(
      eyebrow: 'Help Center',
      title: 'Frequently Asked Questions',
      subtitle: 'Find quick answers to the most common questions about booking, payments, deposits, '
          'extensions, returns, and equipment care.',
      noticeText: 'For a question specific to your booking, contact the team through the official Contact page.',
      currentPath: '/faq',
      body: Column(
        children: [
          for (var i = 0; i < _items.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.white,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_items[i].$1, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(_items[i].$2, style: const TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.charcoal)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}