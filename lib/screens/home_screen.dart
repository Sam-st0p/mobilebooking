// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';

/// Port of `app/page.tsx` (home). The web version's Hero pulls live
/// products for a showcase strip + Navbar for site-wide nav — on mobile,
/// navigation lives in the bottom nav / app shell instead, so this screen
/// focuses on the hero + about + how-it-works + guide sections.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const _guides = [
    (
      route: '/how-to-book',
      label: 'How to Book',
      description: 'Follow the booking process from choosing dates to receiving your rental.',
    ),
    (
      route: '/rental-requirements',
      label: 'Rental Requirements',
      description: 'Prepare the IDs, profiles, contact details, and agreement needed to rent.',
    ),
    (
      route: '/terms',
      label: 'Terms & Conditions',
      description: 'Review deposits, schedules, item care, cancellations, and rental policies.',
    ),
    (
      route: '/faq',
      label: 'FAQs',
      description: 'Find quick answers about reservations, payments, extensions, and returns.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 340,
            pinned: true,
            backgroundColor: AppColors.textPrimary,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primary, AppColors.textPrimary],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(20, 64, 20, 20),
                // SingleChildScrollView (instead of a plain Column) keeps this
                // from overflowing on shorter screens or larger text-scale
                // settings — it'll scroll internally rather th0an clip/overflow.
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  reverse: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('PREMIUM RENTALS · METRO MANILA',
                          style: TextStyle(color: AppColors.blush, fontSize: 12, letterSpacing: 1.2)),
                      const SizedBox(height: 10),
                      const Text(
                        'Rent the Gear.\nCreate the Moment.',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Premium cameras and iPhones for daily rental. Quality equipment, '
                        'simple booking, and transparent pricing—all in one place.',
                        style: TextStyle(color: AppColors.blush, fontSize: 14),
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton.icon(
                        onPressed: () => context.go('/catalog'),
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: const Text('Check Availability'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 32, 20, 8),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _eyebrow('ABOUT US'),
                _heading('The story behind Maddy & Cassy'),
                const SizedBox(height: 8),
                const Text(
                  'IOS Rental by Maddy & Cassy was built from the ground up through '
                  'hard work, careful planning, and a genuine love for helping people '
                  'capture the moments that matter most.',
                  style: TextStyle(color: AppColors.charcoal, height: 1.5),
                ),
                const SizedBox(height: 24),
                _founderCard(
                  initial: 'K',
                  role: 'Owner & Founder',
                  name: 'Kyla Concepcion',
                  pet: '🐾 Owner of Maddy, her dog',
                  bio: "Kyla built Rental by Maddy & Cassy from an idea into a working "
                      "business, drawing on her love of traveling and attending concerts "
                      "to shape a service that helps others hold onto their own favorite moments.",
                ),
                const SizedBox(height: 16),
                _founderCard(
                  initial: 'K',
                  role: 'Co-Owner',
                  name: 'Kim Antonette Repalda',
                  pet: '🐈 Owner of Cassy, her cat',
                  bio: "Kim is Kyla's best friend and co-owner, working alongside her "
                      "to research the rental industry and put in place the policies and "
                      "processes that keep every booking clear and secure.",
                ),
                const SizedBox(height: 32),
                _eyebrow('HOW IT WORKS'),
                _heading('Quality gear, with a clear rental process.'),
                const SizedBox(height: 16),
                _step('01', 'Choose your gear',
                    'Open the catalog, compare available items, and review the daily rate.'),
                _step('02', 'Send a booking request',
                    'Select your dates, provide the rental requirements, and sign the agreement.'),
                _step('03', 'Follow your booking',
                    'Check your account for approval, pickup or delivery details, and status updates.'),
                const SizedBox(height: 32),
                _eyebrow('BEFORE YOU RENT'),
                _heading('Everything you need for a smooth rental.'),
                const SizedBox(height: 16),
                ..._guides.map((g) => _guideCard(context, g)),
                const SizedBox(height: 32),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _eyebrow(String text) => Text(
        text,
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      );

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          text,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.25),
        ),
      );

  Widget _founderCard({
    required String initial,
    required String role,
    required String name,
    required String pet,
    required String bio,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.blush,
            child: Text(initial, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 10),
          Text(role, style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
          Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          Text(pet, style: const TextStyle(color: AppColors.charcoal, fontSize: 13)),
          const SizedBox(height: 8),
          Text(bio, style: const TextStyle(color: AppColors.charcoal, height: 1.5, fontSize: 13.5)),
        ],
      ),
    );
  }

  Widget _step(String number, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(number,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.dustyRose)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 4),
                Text(description, style: const TextStyle(color: AppColors.charcoal, fontSize: 13.5, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _guideCard(BuildContext context, ({String route, String label, String description}) guide) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.push(guide.route),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(guide.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      const SizedBox(height: 4),
                      Text(guide.description,
                          style: const TextStyle(color: AppColors.charcoal, fontSize: 13)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward, size: 18, color: AppColors.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}