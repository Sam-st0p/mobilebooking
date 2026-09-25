// lib/screens/guide/how_to_book_screen.dart
//
// Ported from the web app's /how-to-book page. Content is fixed business
// copy, not fetched from any API.

import 'package:flutter/material.dart';
import '../../widgets/rental_guide_scaffold.dart';

class HowToBookScreen extends StatelessWidget {
  const HowToBookScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RentalGuideScaffold(
      eyebrow: 'Rental Guide',
      title: 'How to Book',
      subtitle: 'Follow these steps to request your unit, complete verification, and arrange pickup or delivery.',
      noticeText: 'Reservation payments and applicable non-refundable deposits are paid manually via GCash and '
          'verified by our team. Delivery courier costs are arranged separately.',
      currentPath: '/how-to-book',
      body: GuideCardGrid(
        children: [
          GuideCard(
            stepLabel: 'Step 01',
            title: 'Start Your Booking Request',
            body: 'Browse the catalog, choose your preferred unit, and select your rental dates. You may also '
                'contact the team through Facebook or TikTok at @iosrental.maddycassy for assistance.',
          ),
          GuideCard(
            stepLabel: 'Step 02',
            title: 'Tell Us Your Rental Plan',
            body: 'Provide the item you want, your preferred rental dates, the number of rental days, and your '
                'pickup or delivery preference.',
          ),
          GuideCard(
            stepLabel: 'Step 03',
            title: 'Save Your Slot',
            body: 'Review any catalog, birthday-month, or 11th-rental loyalty discounts shown in the checkout '
                'summary. A 50% down payment of the final booking total secures the reservation and is '
                'non-refundable, or you may pay the full amount online.',
          ),
          GuideCard(
            stepLabel: 'Step 04',
            title: 'Confirm Your Identity & Sign',
            body: 'Submit the required verification documents and rental agreement:',
            bullets: [
              'Two valid government-issued or accepted school IDs',
              'A clear selfie while holding an accepted ID',
              'Verified Facebook and Instagram profiles',
              'A signed rental agreement',
              'Complete emergency contact information',
            ],
          ),
          GuideCard(
            stepLabel: 'Step 05',
            title: 'Choose Your Handover Option',
            body: 'Pick up your unit at Right Focus Off Campus — Manuel Hizon, Sta. Cruz, Manila, or arrange '
                'delivery through Grab, Lalamove, or Angkas. Roundtrip delivery fees are handled by the renter.',
          ),
        ],
      ),
    );
  }
}