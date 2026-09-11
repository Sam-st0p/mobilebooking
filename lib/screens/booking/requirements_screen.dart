// lib/screens/booking/requirements_screen.dart
//
// STUBBED — the real requirements flow (idOneFile/idTwoFile/selfieFile +
// emergency contact, submitted together via submitBookingDocuments) hasn't
// been built for mobile yet. See lib/services/requirement_service.dart and
// lib/models/requirement.dart for why the previous version of this screen
// was wrong (it modeled a dynamic per-product-requirement pipeline that
// doesn't exist on the real backend).
//
// This screen is not currently linked from anywhere —
// booking_detail_screen.dart's "Complete Requirements" button points at
// ComingSoonScreen directly. This stub exists only so the file still
// compiles if something does route here, and so it's easy to find when
// it's time to build the real version.
//
// To rebuild properly:
//   1. Add a mobile endpoint mirroring
//      app/api/bookings/[bookingId]/documents/upload/route.ts (Bearer auth
//      instead of session auth).
//   2. Rewrite requirement.dart around RequirementsDraft's shape
//      (src/types/reservationDraft.ts) instead of booking_requirements rows.
//   3. Rebuild this screen's UI around the fixed 3-slot ID/selfie + link +
//      emergency-contact form that StepRequirements.tsx actually presents.

import 'package:flutter/material.dart';
import '../coming_soon_screen.dart';

class RequirementsScreen extends StatelessWidget {
  final String bookingId;
  const RequirementsScreen({super.key, required this.bookingId});

  @override
  Widget build(BuildContext context) {
    return const ComingSoonScreen(
      title: 'Complete Requirements',
      note: 'This step needs rebuilding against the real document flow '
          '(3 ID/selfie uploads + emergency contact, submitted together '
          'via submitBookingDocuments) — the previous version guessed at '
          'a different, incorrect schema. See file header for details.',
    );
  }
}