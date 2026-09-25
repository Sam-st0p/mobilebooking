// lib/screens/guide/terms_screen.dart
//
// Ported from the web app's /terms page. Content is fixed business copy,
// not fetched from any API.

import 'package:flutter/material.dart';
import '../../widgets/rental_guide_scaffold.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RentalGuideScaffold(
      eyebrow: 'Rental Policy',
      title: 'Terms & Conditions',
      subtitle: 'These policies apply to booking requests, verification, equipment handover, proper use, and '
          'return of every rental unit.',
      noticeText: 'Reservation payments and applicable non-refundable deposits are paid manually via GCash and '
          'verified by our team. Courier delivery costs are arranged separately with the rental team.',
      currentPath: '/terms',
      body: Column(
        children: [
          GuideCard(
            stepLabel: '01',
            title: 'Booking in Advance',
            body: 'Reservations should be made ahead of time. Same-day bookings may be accepted when a unit is '
                'available and all requirements are complete; the time-based service fee applies only when the '
                'customer voluntarily chooses a schedule outside normal hours.',
          ),
          SizedBox(height: 16),
          GuideCard(
            stepLabel: '02',
            title: 'Security Deposit',
            body: 'A non-refundable security deposit may apply. The exact amount is shown on the product page '
                'and in the checkout summary before payment.',
          ),
          SizedBox(height: 16),
          GuideCard(
            stepLabel: '03',
            title: 'Special Discounts & Loyalty Perks',
            bullets: [
              'A ₱100 birthday discount applies when the selected rental period overlaps the renter\'s birth '
                  'month and the saved birth date matches a submitted valid ID.',
              'One returned booking equals one loyalty count, regardless of the number of units in that booking.',
              'The loyalty program is tracked under the same customer account. ₱200 is automatically applied to '
                  'the booking made after ten completed rentals — the renter\'s 11th rental.',
              'Discounts cannot reduce the rental-fee portion below zero and do not reduce applicable deposits '
                  'or courier charges.',
            ],
          ),
          SizedBox(height: 16),
          GuideCard(
            stepLabel: '04',
            title: 'Pickup & Return Schedule',
            bullets: [
              'Normal pickup and delivery appointments are scheduled between 9:00 AM and 7:00 PM.',
              'Rentals are valid for 22 hours from the scheduled pickup time, or 21 hours for rentals outside '
                  'Manila.',
              'Late returns incur a ₱100 per hour penalty.',
              'A voluntarily selected pickup or delivery time before 9:00 AM or after 7:00 PM carries a ₱100 '
                  'service fee, subject to availability. The fee is not charged when unit availability forces a '
                  'later time.',
            ],
          ),
          SizedBox(height: 16),
          GuideCard(
            stepLabel: '05',
            title: 'Handling & Use of Equipment',
            body: 'Treat every rented unit with care. Use only the included chargers, cables, and accessories, '
                'and follow the handling guidance provided during release.',
          ),
          SizedBox(height: 16),
          GuideCard(
            stepLabel: '06',
            title: 'Damage, Loss, or Theft',
            body: 'Damage, water exposure, or missing parts and accessories will be charged accordingly. In the '
                'event of loss or theft, the renter is responsible for the applicable full replacement cost.',
          ),
          SizedBox(height: 16),
          GuideCard(
            stepLabel: '07',
            title: 'Item Condition',
            body: 'Units are sanitized, reset, and tested before release. Inspect the unit at pickup or '
                'immediately upon delivery and report any issue at once.',
          ),
          SizedBox(height: 16),
          GuideCard(
            stepLabel: '08',
            title: 'Inspection & Checklist',
            body: 'Every unit is inspected at release and return. All listed inclusions and accessories must be '
                'returned in the same condition.',
          ),
          SizedBox(height: 16),
          GuideCard(
            stepLabel: '09',
            title: 'Verification & Requirements',
            bullets: [
              'Two valid government-issued or accepted school IDs and a selfie holding an ID',
              'Active personal Facebook and Instagram accounts',
              'A signed rental agreement',
              "Emergency contact's valid ID, Facebook link, and active phone number",
            ],
          ),
          SizedBox(height: 16),
          GuideCard(
            stepLabel: '10',
            title: 'Cancellation & Refund Policy',
            bullets: [
              'Down payments are non-refundable because the unit is exclusively reserved.',
              'Cancellations made at least 48 hours in advance may be considered for rebooking, subject to '
                  'availability.',
              'Cancellations within 24 hours are non-refundable unless caused by a documented emergency '
                  'accepted by the rental team.',
            ],
          ),
        ],
      ),
    );
  }
}