// lib/models/requirement.dart
//
// Models the real document-requirements pipeline:
//   product_requirements (definitions, per-product) -> booking_requirements
//   (per-booking snapshot, auto-created by create_booking) ->
//   booking_requirement_submissions (each upload attempt) ->
//   customer_documents (the actual uploaded file).
//
// booking_requirements.status is the source of truth for whether a
// requirement is satisfied. It's expected to move pending_submission ->
// pending_review (once a submission exists) -> approved/rejected/waived
// (admin decision). There is NO client-facing RPC for any of this — see
// RequirementService for the direct-table-insert approach and the caveat
// that comes with it.

enum RequirementStatus { pendingSubmission, pendingReview, approved, rejected, waived }

RequirementStatus requirementStatusFromString(String value) {
  switch (value) {
    case 'pending_submission':
      return RequirementStatus.pendingSubmission;
    case 'pending_review':
      return RequirementStatus.pendingReview;
    case 'approved':
      return RequirementStatus.approved;
    case 'rejected':
      return RequirementStatus.rejected;
    case 'waived':
      return RequirementStatus.waived;
    default:
      return RequirementStatus.pendingSubmission;
  }
}

String requirementStatusLabel(RequirementStatus status) {
  switch (status) {
    case RequirementStatus.pendingSubmission:
      return 'Needs Upload';
    case RequirementStatus.pendingReview:
      return 'Under Review';
    case RequirementStatus.approved:
      return 'Approved';
    case RequirementStatus.rejected:
      return 'Rejected — Re-upload';
    case RequirementStatus.waived:
      return 'Waived';
  }
}

/// A requirement is "satisfied" (no further customer action needed) once
/// it's approved or waived.
bool requirementIsSatisfied(RequirementStatus status) =>
    status == RequirementStatus.approved || status == RequirementStatus.waived;

enum ReviewDecision { pending, approved, rejected }

ReviewDecision reviewDecisionFromString(String value) {
  switch (value) {
    case 'approved':
      return ReviewDecision.approved;
    case 'rejected':
      return ReviewDecision.rejected;
    default:
      return ReviewDecision.pending;
  }
}

class CustomerDocument {
  final String id;
  final String documentType;
  final String storageBucket;
  final String storagePath;
  final String? originalFilename;
  final String? mimeType;

  const CustomerDocument({
    required this.id,
    required this.documentType,
    required this.storageBucket,
    required this.storagePath,
    this.originalFilename,
    this.mimeType,
  });

  factory CustomerDocument.fromRow(Map<String, dynamic> row) {
    return CustomerDocument(
      id: row['id'] as String,
      documentType: row['document_type'] as String? ?? '',
      storageBucket: row['storage_bucket'] as String? ?? '',
      storagePath: row['storage_path'] as String,
      originalFilename: row['original_filename'] as String?,
      mimeType: row['mime_type'] as String?,
    );
  }
}

class RequirementSubmission {
  final String id;
  final int attemptNumber;
  final ReviewDecision reviewStatus;
  final String? reviewNotes;
  final DateTime submittedAt;
  final DateTime? reviewedAt;
  final CustomerDocument? document;

  const RequirementSubmission({
    required this.id,
    required this.attemptNumber,
    required this.reviewStatus,
    this.reviewNotes,
    required this.submittedAt,
    this.reviewedAt,
    this.document,
  });

  /// Expects a row selected with:
  ///   *, customer_documents(*)
  factory RequirementSubmission.fromRow(Map<String, dynamic> row) {
    final docRow = row['customer_documents'];
    return RequirementSubmission(
      id: row['id'] as String,
      attemptNumber: (row['attempt_number'] as num?)?.toInt() ?? 1,
      reviewStatus: reviewDecisionFromString(row['review_status'] as String? ?? 'pending'),
      reviewNotes: row['review_notes'] as String?,
      submittedAt: DateTime.parse(row['submitted_at'] as String),
      reviewedAt: row['reviewed_at'] != null ? DateTime.parse(row['reviewed_at'] as String) : null,
      document: docRow is Map<String, dynamic> ? CustomerDocument.fromRow(docRow) : null,
    );
  }
}

class BookingRequirement {
  final String id;
  final String bookingId;
  final String requirementKeySnapshot;
  final String requirementNameSnapshot;
  final String documentTypeSnapshot;
  final bool isRequired;
  final RequirementStatus status;
  final String? waiverReason;
  final List<RequirementSubmission> submissions;

  const BookingRequirement({
    required this.id,
    required this.bookingId,
    required this.requirementKeySnapshot,
    required this.requirementNameSnapshot,
    required this.documentTypeSnapshot,
    required this.isRequired,
    required this.status,
    this.waiverReason,
    this.submissions = const [],
  });

  /// Most recent attempt, if any — the one whose review status/notes matter
  /// for what the customer sees.
  RequirementSubmission? get latestSubmission =>
      submissions.isEmpty ? null : submissions.reduce((a, b) => a.attemptNumber >= b.attemptNumber ? a : b);

  bool get isSatisfied => requirementIsSatisfied(status);

  bool get needsAction =>
      status == RequirementStatus.pendingSubmission || status == RequirementStatus.rejected;

  /// Expects a row selected with:
  ///   *, booking_requirement_submissions(*, customer_documents(*))
  factory BookingRequirement.fromRow(Map<String, dynamic> row) {
    final subRows = (row['booking_requirement_submissions'] as List?) ?? [];
    return BookingRequirement(
      id: row['id'] as String,
      bookingId: row['booking_id'] as String,
      requirementKeySnapshot: row['requirement_key_snapshot'] as String? ?? '',
      requirementNameSnapshot: row['requirement_name_snapshot'] as String? ?? 'Requirement',
      documentTypeSnapshot: row['document_type_snapshot'] as String? ?? '',
      isRequired: row['is_required'] as bool? ?? true,
      status: requirementStatusFromString(row['status'] as String? ?? 'pending_submission'),
      waiverReason: row['waiver_reason'] as String?,
      submissions:
          subRows.map((r) => RequirementSubmission.fromRow(r as Map<String, dynamic>)).toList(),
    );
  }
}