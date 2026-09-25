// lib/screens/guide/rental_requirements_screen.dart
//
// Ported from the web app's /rental-requirements page. Content is fixed
// business copy, not fetched from any API.

import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/rental_guide_scaffold.dart';

class RentalRequirementsScreen extends StatelessWidget {
  const RentalRequirementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return RentalGuideScaffold(
      eyebrow: 'Before You Book',
      title: 'Rental Requirements',
      subtitle: 'Prepare these requirements before submitting your booking so the team can verify your request '
          'without delays.',
      currentPath: '/rental-requirements',
      body: GuideCardGrid(
        children: [
          const GuideCard(
            stepLabel: '01',
            title: 'Two Valid IDs',
            body: 'Provide two valid government-issued or accepted school IDs. At least one must show your '
                'current address and signature.',
            bullets: ['Passport', 'National ID', "Driver's license", 'Student ID or another accepted valid ID'],
          ),
          GuideCard(
            stepLabel: '02',
            title: 'Verified Facebook & Instagram Profiles',
            body: 'Both profiles must be your primary personal social media accounts and must be available for '
                'verification.',
            insetBox: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Requests may not be processed when:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  SizedBox(height: 6),
                  BulletList(items: [
                    'An account is private or locked',
                    'A profile is newly created or appears suspicious',
                    'An account has no profile picture or appears to be a dummy account',
                  ]),
                ],
              ),
            ),
          ),
          const GuideCard(
            stepLabel: '03',
            title: 'Emergency Contact Information',
            body: 'Provide a relative or immediate family member who may be contacted in an emergency or '
                'rental-related issue.',
            bullets: ['Full name and Facebook account', 'Active phone number', "Photo of their valid government-issued ID"],
          ),
          const GuideCard(
            stepLabel: '04',
            title: 'Rental Contract Agreement',
            body: 'Every renter must review and sign a rental agreement. The agreement protects both parties '
                'and documents responsibilities concerning the rented unit, accessories, loss, damage, and '
                'proper use.',
          ),
        ],
      ),
    );
  }
}