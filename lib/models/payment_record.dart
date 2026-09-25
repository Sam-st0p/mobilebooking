// lib/models/payment_record.dart

/// One row from GET /account/payments.
class PaymentRecord {
  final String id;
  final String bookingId;
  final String bookingReference;
  final String productName;

  /// "down_payment" | "full" | "balance"
  final String stage;

  /// "submitted" | "under_review" | "verified" | "rejected"
  final String status;

  final double amount;
  final String paymentMethod;
  final String referenceNumber;
  final String? proofUrl;
  final DateTime submittedAt;

  const PaymentRecord({
    required this.id,
    required this.bookingId,
    required this.bookingReference,
    required this.productName,
    required this.stage,
    required this.status,
    required this.amount,
    required this.paymentMethod,
    required this.referenceNumber,
    required this.submittedAt,
    this.proofUrl,
  });

  factory PaymentRecord.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) => v is String ? (DateTime.tryParse(v) ?? DateTime.now()) : DateTime.now();

    return PaymentRecord(
      id: (json['id'] as String?) ?? '',
      bookingId: (json['bookingId'] as String?) ?? '',
      bookingReference: (json['bookingReference'] as String?) ?? '',
      productName: (json['productName'] as String?) ?? 'Rental',
      stage: (json['stage'] as String?) ?? 'down_payment',
      status: (json['status'] as String?) ?? 'submitted',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      paymentMethod: (json['paymentMethod'] as String?) ?? 'gcash',
      referenceNumber: (json['referenceNumber'] as String?) ?? '',
      proofUrl: json['proofUrl'] as String?,
      submittedAt: parseDate(json['submittedAt']),
    );
  }

  String get stageLabel => switch (stage) {
        'down_payment' => 'Down payment (50%)',
        'full' => 'Full payment',
        'balance' => 'Balance payment',
        _ => stage,
      };

  String get statusLabel => switch (status) {
        'submitted' => 'Submitted',
        'under_review' => 'Under review',
        'verified' => 'Verified',
        'rejected' => 'Rejected',
        _ => status,
      };
}