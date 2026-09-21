// lib/models/booking_detail.dart
//
// Everything the Guest Booking Tracker's Progress/Documents/Updates tabs
// need, beyond the base Booking object. Mirrors the extra keys added to
// GET /api/mobile/account/bookings/:id by
// BookingController::fetchBookingDetailExtras(), which in turn mirrors
// src/services/bookingDetailService.ts::getBookingDetails on the real app.
//
// The 6-milestone tracker and 4-step progress card are NOT modeled here —
// they're pure UI-derived logic on the real app (getBookingMilestones,
// the processSteps array in bookingManagement.ts / the account bookings
// page), computed from fields already on Booking (status, approvedAt,
// confirmedAt, etc.). Compute them client-side in Flutter the same way,
// don't expect them from the API.

import 'booking.dart';

class AgreementSignature {
  final String id;
  final String agreementVersionId;
  final String? signerUserId;
  final String signerRole; // "customer" | "business" | ...
  final String signerName;
  final String? signaturePath;
  final Map<String, dynamic> signatureData;
  final String? ipAddress;
  final String? userAgent;
  final DateTime signedAt;

  const AgreementSignature({
    required this.id,
    required this.agreementVersionId,
    this.signerUserId,
    required this.signerRole,
    required this.signerName,
    this.signaturePath,
    this.signatureData = const {},
    this.ipAddress,
    this.userAgent,
    required this.signedAt,
  });

  factory AgreementSignature.fromJson(Map<String, dynamic> json) {
    return AgreementSignature(
      id: json['id'] as String,
      agreementVersionId: json['agreementVersionId'] as String,
      signerUserId: json['signerUserId'] as String?,
      signerRole: json['signerRole'] as String? ?? 'customer',
      signerName: json['signerName'] as String? ?? '',
      signaturePath: json['signaturePath'] as String?,
      signatureData: (json['signatureData'] as Map<String, dynamic>?) ?? const {},
      ipAddress: json['ipAddress'] as String?,
      userAgent: json['userAgent'] as String?,
      signedAt: DateTime.parse(json['signedAt'] as String),
    );
  }
}

class AgreementDoc {
  final String id;
  final String bookingId;
  final String status; // "not_created" | "awaiting_customer_signature" | "awaiting_business_signature" | "completed" | "rejected"
  final String? currentVersionId;
  final int? versionNumber;
  final Map<String, dynamic>? agreementSnapshot;
  final String? generatedDocumentPath;
  final String? finalDocumentPath;
  final DateTime? generatedAt;
  final DateTime? completedAt;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<AgreementSignature> signatures;

  const AgreementDoc({
    required this.id,
    required this.bookingId,
    required this.status,
    this.currentVersionId,
    this.versionNumber,
    this.agreementSnapshot,
    this.generatedDocumentPath,
    this.finalDocumentPath,
    this.generatedAt,
    this.completedAt,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.signatures = const [],
  });

  factory AgreementDoc.fromJson(Map<String, dynamic> json) {
    DateTime? parseOpt(String? key) => json[key] != null ? DateTime.parse(json[key] as String) : null;
    return AgreementDoc(
      id: json['id'] as String,
      bookingId: json['bookingId'] as String,
      status: json['status'] as String? ?? 'not_created',
      currentVersionId: json['currentVersionId'] as String?,
      versionNumber: (json['versionNumber'] as num?)?.toInt(),
      agreementSnapshot: json['agreementSnapshot'] as Map<String, dynamic>?,
      generatedDocumentPath: json['generatedDocumentPath'] as String?,
      finalDocumentPath: json['finalDocumentPath'] as String?,
      generatedAt: parseOpt('generatedAt'),
      completedAt: parseOpt('completedAt'),
      createdBy: json['createdBy'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      signatures: ((json['signatures'] as List?) ?? [])
          .map((e) => AgreementSignature.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// One reviewable file (government ID, secondary ID, selfie with ID,
/// authorization letter). Mirrors BookingDocument in booking.ts — assembled
/// dynamically from booking_requirements + its latest submission, not a
/// standalone table.
class BookingDocument {
  final String id;
  final String bookingId;
  final String requirementId;
  final String documentType; // "government_id" | "secondary_id" | "selfie_with_id" | "authorization_letter"
  final String requirementKey;
  final String storageBucket;
  final String storagePath;
  final String? originalFilename;
  final String? mimeType;
  final int? fileSizeBytes;
  final String reviewStatus; // "pending" | "approved" | "rejected"
  final String? reviewNotes;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BookingDocument({
    required this.id,
    required this.bookingId,
    required this.requirementId,
    required this.documentType,
    required this.requirementKey,
    this.storageBucket = '',
    this.storagePath = '',
    this.originalFilename,
    this.mimeType,
    this.fileSizeBytes,
    required this.reviewStatus,
    this.reviewNotes,
    this.reviewedBy,
    this.reviewedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BookingDocument.fromJson(Map<String, dynamic> json) {
    DateTime? parseOpt(String? key) => json[key] != null ? DateTime.parse(json[key] as String) : null;
    return BookingDocument(
      id: json['id'] as String,
      bookingId: json['bookingId'] as String,
      requirementId: json['requirementId'] as String,
      documentType: json['documentType'] as String? ?? '',
      requirementKey: json['requirementKey'] as String? ?? '',
      storageBucket: json['storageBucket'] as String? ?? '',
      storagePath: json['storagePath'] as String? ?? '',
      originalFilename: json['originalFilename'] as String?,
      mimeType: json['mimeType'] as String?,
      fileSizeBytes: (json['fileSizeBytes'] as num?)?.toInt(),
      reviewStatus: json['reviewStatus'] as String? ?? 'pending',
      reviewNotes: json['reviewNotes'] as String?,
      reviewedBy: json['reviewedBy'] as String?,
      reviewedAt: parseOpt('reviewedAt'),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  String get displayLabel => documentType
      .split('_')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

class StatusHistoryEntry {
  final String id;
  final String bookingId;
  final String? fromStatus;
  final String toStatus;
  final String? note;
  final String? changedByUserId;
  final DateTime createdAt;

  const StatusHistoryEntry({
    required this.id,
    required this.bookingId,
    this.fromStatus,
    required this.toStatus,
    this.note,
    this.changedByUserId,
    required this.createdAt,
  });

  factory StatusHistoryEntry.fromJson(Map<String, dynamic> json) {
    return StatusHistoryEntry(
      id: json['id'] as String,
      bookingId: json['bookingId'] as String,
      fromStatus: json['fromStatus'] as String?,
      toStatus: json['toStatus'] as String? ?? '',
      note: json['note'] as String?,
      changedByUserId: json['changedByUserId'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

/// Field names beyond bookingId/stage/status/createdAt are best-effort —
/// paymentService.ts (mapPaymentSubmission) was never confirmed against
/// real source. Treat declaredAmount/paymentMethod/externalReference/
/// providerMetadata as provisional until that's checked.
class PaymentSubmission {
  final String id;
  final String bookingId;
  final String? stage;
  final String status; // "submitted" | "under_review" | "verified" | "rejected" (confirmed values)
  final double? declaredAmount;
  final String? paymentMethod;
  final String? externalReference;
  final Map<String, dynamic>? providerMetadata;
  final DateTime createdAt;

  const PaymentSubmission({
    required this.id,
    required this.bookingId,
    this.stage,
    required this.status,
    this.declaredAmount,
    this.paymentMethod,
    this.externalReference,
    this.providerMetadata,
    required this.createdAt,
  });

  factory PaymentSubmission.fromJson(Map<String, dynamic> json) {
    return PaymentSubmission(
      id: json['id'] as String,
      bookingId: json['bookingId'] as String,
      stage: json['stage'] as String?,
      status: json['status'] as String? ?? 'submitted',
      declaredAmount: (json['declaredAmount'] as num?)?.toDouble(),
      paymentMethod: json['paymentMethod'] as String?,
      externalReference: json['externalReference'] as String?,
      providerMetadata: json['providerMetadata'] as Map<String, dynamic>?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  /// Matches the real web app's isDemoPayment check:
  /// providerMetadata?.demo === true.
  bool get isDemo => providerMetadata?['demo'] == true;
}

class BookingReceipt {
  final String id;
  final String bookingId;
  final String? paymentSubmissionId;
  final String receiptNumber;
  final double amount;
  final DateTime issuedAt;
  final String? documentPath;
  final String? issuedBy;
  final DateTime? emailedAt;
  final String? emailedTo;
  final DateTime createdAt;

  const BookingReceipt({
    required this.id,
    required this.bookingId,
    this.paymentSubmissionId,
    required this.receiptNumber,
    required this.amount,
    required this.issuedAt,
    this.documentPath,
    this.issuedBy,
    this.emailedAt,
    this.emailedTo,
    required this.createdAt,
  });

  factory BookingReceipt.fromJson(Map<String, dynamic> json) {
    DateTime? parseOpt(String? key) => json[key] != null ? DateTime.parse(json[key] as String) : null;
    return BookingReceipt(
      id: json['id'] as String,
      bookingId: json['bookingId'] as String,
      paymentSubmissionId: json['paymentSubmissionId'] as String?,
      receiptNumber: json['receiptNumber'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      issuedAt: DateTime.parse(json['issuedAt'] as String),
      documentPath: json['documentPath'] as String?,
      issuedBy: json['issuedBy'] as String?,
      emailedAt: parseOpt('emailedAt'),
      emailedTo: json['emailedTo'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class BookingReview {
  final String id;
  final int rating;
  final String? comment;
  final String status; // "pending" | "approved" | "rejected"
  final DateTime createdAt;

  const BookingReview({
    required this.id,
    required this.rating,
    this.comment,
    required this.status,
    required this.createdAt,
  });

  factory BookingReview.fromJson(Map<String, dynamic> json) {
    return BookingReview(
      id: json['id'] as String,
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      comment: json['comment'] as String?,
      status: json['status'] as String? ?? 'pending',
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class EmergencyContact {
  final String bookingId;
  final String fullName;
  final String relationship;
  final String phoneNumber;
  final String? address;

  const EmergencyContact({
    required this.bookingId,
    required this.fullName,
    required this.relationship,
    required this.phoneNumber,
    this.address,
  });

  factory EmergencyContact.fromJson(Map<String, dynamic> json) {
    return EmergencyContact(
      bookingId: json['bookingId'] as String,
      fullName: json['fullName'] as String? ?? '',
      relationship: json['relationship'] as String? ?? '',
      phoneNumber: json['phoneNumber'] as String? ?? '',
      address: json['address'] as String?,
    );
  }
}

/// Mirrors booking_cancellation_requests, confirmed against
/// bookingService.ts's mapCancellationRequest.
class CancellationRequest {
  final String id;
  final String bookingId;
  final String customerId;
  final String? requestedStatus;
  final String reason;
  final String? additionalDetails;
  final String status; // "pending" | "approved" | "rejected"
  final String? decisionNote;
  final String? decidedBy;
  final DateTime requestedAt;
  final DateTime? decidedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CancellationRequest({
    required this.id,
    required this.bookingId,
    required this.customerId,
    this.requestedStatus,
    required this.reason,
    this.additionalDetails,
    required this.status,
    this.decisionNote,
    this.decidedBy,
    required this.requestedAt,
    this.decidedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CancellationRequest.fromJson(Map<String, dynamic> json) {
    DateTime? parseOpt(String? key) => json[key] != null ? DateTime.parse(json[key] as String) : null;
    return CancellationRequest(
      id: json['id'] as String,
      bookingId: json['bookingId'] as String,
      customerId: json['customerId'] as String? ?? '',
      requestedStatus: json['requestedStatus'] as String?,
      reason: json['reason'] as String? ?? '',
      additionalDetails: json['additionalDetails'] as String?,
      status: json['status'] as String? ?? 'pending',
      decisionNote: json['decisionNote'] as String?,
      decidedBy: json['decidedBy'] as String?,
      requestedAt: DateTime.parse(json['requestedAt'] as String),
      decidedAt: parseOpt('decidedAt'),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  bool get isPending => status == 'pending';
}

/// Wraps the full GET /account/bookings/:id response: the base Booking
/// plus everything the tracker's Progress/Documents/Updates tabs need.
class BookingDetail {
  final Booking booking;
  final EmergencyContact? emergencyContact;
  final AgreementDoc? agreement;
  final List<StatusHistoryEntry> statusHistory;
  final List<BookingDocument> documents;
  final List<PaymentSubmission> payments;
  final List<BookingReceipt> receipts;
  final BookingReview? review;
  final CancellationRequest? cancellationRequest;

  const BookingDetail({
    required this.booking,
    this.emergencyContact,
    this.agreement,
    this.statusHistory = const [],
    this.documents = const [],
    this.payments = const [],
    this.receipts = const [],
    this.review,
    this.cancellationRequest,
  });

  factory BookingDetail.fromJson(Map<String, dynamic> json) {
    return BookingDetail(
      booking: Booking.fromJson(json['booking'] as Map<String, dynamic>),
      emergencyContact: json['emergencyContact'] != null
          ? EmergencyContact.fromJson(json['emergencyContact'] as Map<String, dynamic>)
          : null,
      agreement: json['agreement'] != null
          ? AgreementDoc.fromJson(json['agreement'] as Map<String, dynamic>)
          : null,
      statusHistory: ((json['statusHistory'] as List?) ?? [])
          .map((e) => StatusHistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      documents: ((json['documents'] as List?) ?? [])
          .map((e) => BookingDocument.fromJson(e as Map<String, dynamic>))
          .toList(),
      payments: ((json['payments'] as List?) ?? [])
          .map((e) => PaymentSubmission.fromJson(e as Map<String, dynamic>))
          .toList(),
      receipts: ((json['receipts'] as List?) ?? [])
          .map((e) => BookingReceipt.fromJson(e as Map<String, dynamic>))
          .toList(),
      review: json['review'] != null ? BookingReview.fromJson(json['review'] as Map<String, dynamic>) : null,
      cancellationRequest: json['cancellationRequest'] != null
          ? CancellationRequest.fromJson(json['cancellationRequest'] as Map<String, dynamic>)
          : null,
    );
  }

  bool get hasVerifiedPayment => payments.any((p) => p.status == 'verified');
  bool get hasLockedProgress =>
      payments.any((p) => ['submitted', 'under_review', 'verified'].contains(p.status)) ||
      documents.isNotEmpty ||
      agreement != null;
  bool get hasPendingCancellation => cancellationRequest?.isPending ?? false;
}