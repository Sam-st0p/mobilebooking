// lib/services/requirement_service.dart
//
// DISABLED — this modeled the wrong schema. It was built assuming a
// dynamic "one row per product requirement" model
// (product_requirements -> booking_requirements -> booking_requirement_
// submissions -> customer_documents), but the real web app
// (components/reservation/StepRequirements.tsx) actually uses a FIXED set
// of uploads bundled into the reservation submission itself:
//   idOneFile, idTwoFile, selfieFile, facebookLink, instagramLink,
//   emergencyContact — see RequirementsDraft in
//   src/types/reservationDraft.ts, submitted together via
//   submitBookingDocuments(bookingId, draft) in
//   src/services/bookingSubmissionService.ts, gated behind the customer
//   having already submitted payment proof (see
//   app/api/bookings/[bookingId]/documents/upload/route.ts).
//
// Rebuilding this correctly means:
//   1. A new mobile endpoint (e.g. POST /api/mobile/account/bookings/:id/
//      documents?kind=idOne|idTwo|selfie|emergencyId|signature) mirroring
//      that upload route's multipart handling, adapted for Bearer auth.
//   2. Rewriting requirement.dart around RequirementsDraft's shape instead
//      of booking_requirements rows.
//   3. Rewriting requirements_screen.dart's UI around the fixed 3-slot +
//      emergency-contact form StepRequirements.tsx actually presents.
//
// Left as a stub (rather than deleted) so booking_detail_screen.dart's
// "Complete Requirements" button has something safe to point at in the
// meantime — see ComingSoonScreen usage there.

class RequirementServiceDisabled implements Exception {
  final String message = 'This feature needs to be rebuilt against the real requirements flow. See file header.';
  @override
  String toString() => message;
}
