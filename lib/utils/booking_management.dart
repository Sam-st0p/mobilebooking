// lib/utils/booking_management.dart
//
// Direct port of src/lib/bookingManagement.ts. This logic is pure UI
// derivation on the real app — no server endpoint returns it — so it's
// ported here rather than requested from the backend.

import '../models/booking.dart';
import '../models/booking_detail.dart';

class BookingMilestone {
  final String key;
  final String label;
  final String description;
  final bool completed;
  final bool current;
  final DateTime? timestamp;

  const BookingMilestone({
    required this.key,
    required this.label,
    required this.description,
    required this.completed,
    required this.current,
    this.timestamp,
  });
}

const _order = <BookingStatus>[
  BookingStatus.pending,
  BookingStatus.approved,
  BookingStatus.confirmed,
  BookingStatus.readyForRelease,
  BookingStatus.released,
  BookingStatus.returned,
];

/// The 6-milestone "From request to completion" tracker.
/// Mirrors getBookingMilestones() exactly.
List<BookingMilestone> bookingMilestones(Booking booking) {
  final isClosed = booking.status == BookingStatus.cancelled || booking.status == BookingStatus.rejected;
  final currentIndex = _order.indexOf(booking.status);
  final fulfillment = booking.fulfillmentMethod == FulfillmentMethod.delivery ? 'delivery' : 'pickup';

  final milestones = <BookingMilestone>[
    BookingMilestone(
      key: 'submitted',
      label: 'Request submitted',
      description: 'Booking reference created and rental dates reserved.',
      completed: true,
      current: booking.status == BookingStatus.pending,
      timestamp: booking.createdAt,
    ),
    BookingMilestone(
      key: 'approved',
      label: 'Request approved',
      description: 'The business reviewed and approved the rental request.',
      completed: currentIndex >= 1 && !isClosed,
      current: booking.status == BookingStatus.approved,
      timestamp: booking.approvedAt,
    ),
    BookingMilestone(
      key: 'confirmed',
      label: 'Booking confirmed',
      description: 'Payment, documents, and agreement requirements are complete.',
      completed: currentIndex >= 2 && !isClosed,
      current: booking.status == BookingStatus.confirmed,
      timestamp: booking.confirmedAt,
    ),
    BookingMilestone(
      key: 'ready',
      label: 'Ready for $fulfillment',
      description: 'The rental item is prepared for $fulfillment.',
      completed: currentIndex >= 3 && !isClosed,
      current: booking.status == BookingStatus.readyForRelease,
      timestamp: booking.readyForReleaseAt,
    ),
    BookingMilestone(
      key: 'released',
      label: booking.fulfillmentMethod == FulfillmentMethod.delivery ? 'Delivered / received' : 'Released at pickup',
      description: 'The rental item was handed over to the customer.',
      completed: currentIndex >= 4 && !isClosed,
      current: booking.status == BookingStatus.released,
      timestamp: booking.releasedAt,
    ),
    BookingMilestone(
      key: 'completed',
      label: 'Rental completed',
      description: 'The item was returned and the booking was completed.',
      completed: booking.status == BookingStatus.returned,
      current: booking.status == BookingStatus.returned,
      timestamp: booking.returnedAt,
    ),
  ];

  if (isClosed) {
    milestones.add(BookingMilestone(
      key: 'closed',
      label: booking.status == BookingStatus.cancelled ? 'Booking cancelled' : 'Request declined',
      description: booking.status == BookingStatus.cancelled
          ? 'The reserved dates were released.'
          : 'The request was closed by the business.',
      completed: true,
      current: true,
      timestamp: booking.status == BookingStatus.cancelled ? booking.cancelledAt : booking.rejectedAt,
    ));
  }

  return milestones;
}

/// Mirrors getBookingStatusMessage().
String bookingStatusMessage(BookingStatus status, FulfillmentMethod fulfillmentMethod) {
  final handover = fulfillmentMethod == FulfillmentMethod.delivery ? 'delivery' : 'pickup';
  switch (status) {
    case BookingStatus.draft:
      return 'Complete the remaining booking steps to submit this request.';
    case BookingStatus.pending:
      return 'Your request is being reviewed. You may still cancel it or edit safe details.';
    case BookingStatus.approved:
      return 'Your request is approved. Complete any remaining payment and verification steps.';
    case BookingStatus.confirmed:
      return 'Your booking is confirmed. We will update you when it is ready for $handover.';
    case BookingStatus.readyForRelease:
      return 'Your rental is prepared and ready for $handover.';
    case BookingStatus.released:
      return fulfillmentMethod == FulfillmentMethod.delivery
          ? 'Your rental has been handed over for delivery or received by you.'
          : 'Your rental has been released to you.';
    case BookingStatus.returned:
      return 'The rental was returned and this booking is complete.';
    case BookingStatus.cancelled:
      return 'This booking was cancelled and its reserved dates were released.';
    case BookingStatus.rejected:
      return 'This request was not approved. Open the details for the administrator note.';
  }
}

/// Mirrors getFulfillmentProgressLabel().
String fulfillmentProgressLabel(BookingStatus status, FulfillmentMethod fulfillmentMethod) {
  if (status == BookingStatus.returned) return 'Completed';
  if (status == BookingStatus.cancelled) return 'Closed';
  if (status == BookingStatus.rejected) return 'Rejected';
  if (status == BookingStatus.released) {
    return fulfillmentMethod == FulfillmentMethod.delivery ? 'Out for delivery / received' : 'Picked up';
  }
  if (status == BookingStatus.readyForRelease) {
    return fulfillmentMethod == FulfillmentMethod.delivery ? 'Ready for delivery' : 'Ready for pickup';
  }
  if (status == BookingStatus.confirmed) return 'Preparing item';
  return fulfillmentMethod == FulfillmentMethod.delivery ? 'Delivery pending' : 'Pickup pending';
}

/// Mirrors canCustomerCancelBooking(). NOTE: also check
/// !detail.hasPendingCancellation at the call site — the real UI ANDs
/// both conditions together (see CustomerBookingManagement.tsx).
bool canCustomerCancelBooking(BookingStatus status) {
  return status == BookingStatus.pending || status == BookingStatus.approved;
}

/// Mirrors canCustomerEditBooking(). NOTE: also check
/// !detail.hasPendingCancellation at the call site, same as above.
bool canCustomerEditBooking(Booking booking, bool hasLockedProgress) {
  return booking.status == BookingStatus.pending && !hasLockedProgress;
}

/// The 4-step "Payment / Documents / Agreement / Confirmation" progress
/// card. Mirrors the `processSteps` array built inline on the real app's
/// account/bookings/[bookingId]/page.tsx — not a named exported function
/// there, so this is ported from that page's logic directly.
class ProcessStep {
  final String label;
  final String value;
  final String help;
  final String state; // "complete" | "current" | "attention" | "upcoming"

  const ProcessStep({required this.label, required this.value, required this.help, required this.state});

  bool get isComplete => state == 'complete';
}

const _requirementsStatusLabel = <String, String>{
  'not_submitted': 'Not Submitted',
  'pending_review': 'Pending Review',
  'approved': 'Approved',
  'rejected': 'Rejected',
};

const _agreementStatusLabel = <String, String>{
  'not_created': 'Not Created',
  'awaiting_customer_signature': 'Awaiting Your Signature',
  'awaiting_business_signature': 'Awaiting Business Signature',
  'completed': 'Completed',
  'rejected': 'Rejected',
};

const _completedBookingStatuses = <BookingStatus>{
  BookingStatus.confirmed,
  BookingStatus.readyForRelease,
  BookingStatus.released,
  BookingStatus.returned,
};

String _requirementGuidance(String status) {
  switch (status) {
    case 'approved':
      return 'Your identity documents have been reviewed and accepted.';
    case 'pending_review':
      return 'Your documents are with the team for review. No action is needed right now.';
    case 'rejected':
      return 'One or more documents need to be corrected. See the review notes below.';
    default:
      return 'Submit the requested verification documents to continue.';
  }
}

String _agreementGuidance(String status) {
  switch (status) {
    case 'completed':
      return 'The rental agreement has all required signatures and is ready to view.';
    case 'awaiting_business_signature':
      return "Your part is complete—no action is needed from you. An administrator will finish reviewing your documents, countersign the agreement, and notify you when the final PDF is ready.";
    case 'awaiting_customer_signature':
      return 'Review and sign the rental agreement to continue your booking.';
    case 'rejected':
      return 'The agreement needs attention. Please contact the business for assistance.';
    default:
      return 'Your agreement will be prepared after the required booking steps.';
  }
}

List<ProcessStep> bookingProcessSteps(BookingDetail detail) {
  final booking = detail.booking;
  final hasVerifiedPayment = detail.hasVerifiedPayment;

  final requirementsState = booking.requirementsStatus == 'approved'
      ? 'complete'
      : booking.requirementsStatus == 'rejected'
          ? 'attention'
          : booking.requirementsStatus == 'pending_review'
              ? 'current'
              : 'upcoming';

  final agreementState = booking.agreementStatus == 'completed'
      ? 'complete'
      : booking.agreementStatus == 'rejected'
          ? 'attention'
          : booking.agreementStatus == 'not_created'
              ? 'upcoming'
              : 'current';

  final confirmed = _completedBookingStatuses.contains(booking.status);

  return [
    ProcessStep(
      label: 'Payment',
      value: hasVerifiedPayment ? 'Verified' : 'Not yet verified',
      help: hasVerifiedPayment
          ? 'Your payment was securely verified and recorded.'
          : 'Complete or resume your secure payment to reserve the selected dates.',
      state: hasVerifiedPayment ? 'complete' : 'current',
    ),
    ProcessStep(
      label: 'Documents',
      value: _requirementsStatusLabel[booking.requirementsStatus] ?? booking.requirementsStatus,
      help: _requirementGuidance(booking.requirementsStatus),
      state: requirementsState,
    ),
    ProcessStep(
      label: 'Agreement',
      value: _agreementStatusLabel[booking.agreementStatus] ?? booking.agreementStatus,
      help: _agreementGuidance(booking.agreementStatus),
      state: agreementState,
    ),
    ProcessStep(
      label: 'Confirmation',
      value: confirmed ? 'Confirmed' : 'In progress',
      help: confirmed
          ? 'The booking is confirmed. Follow the tracker above for pickup or delivery updates.'
          : 'The business confirms the booking after payment, documents, and agreement are complete.',
      state: confirmed ? 'complete' : 'upcoming',
    ),
  ];
}