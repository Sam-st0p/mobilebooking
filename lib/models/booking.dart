// lib/models/booking.dart

/// Mirrors the `status` check constraint in supabase/booking_schema.sql.
enum BookingStatus {
  pendingReview,
  approved,
  rejected,
  active,
  completed,
  cancelled,
}

BookingStatus bookingStatusFromString(String value) {
  switch (value) {
    case 'pending_review':
      return BookingStatus.pendingReview;
    case 'approved':
      return BookingStatus.approved;
    case 'rejected':
      return BookingStatus.rejected;
    case 'active':
      return BookingStatus.active;
    case 'completed':
      return BookingStatus.completed;
    case 'cancelled':
      return BookingStatus.cancelled;
    default:
      return BookingStatus.pendingReview;
  }
}

String bookingStatusLabel(BookingStatus status) {
  switch (status) {
    case BookingStatus.pendingReview:
      return 'Pending Review';
    case BookingStatus.approved:
      return 'Approved';
    case BookingStatus.rejected:
      return 'Rejected';
    case BookingStatus.active:
      return 'Active';
    case BookingStatus.completed:
      return 'Completed';
    case BookingStatus.cancelled:
      return 'Cancelled';
  }
}

class Booking {
  final String id;
  final String productId;
  final String productName;
  final String productImage;
  final DateTime startDate;
  final DateTime endDate;
  final int quantity;
  final double dailyRateSnapshot;
  final double refundableDepositSnapshot;
  final double subtotal;
  final double totalAmount;
  final BookingStatus status;
  final String paymentStatus;
  final String fullName;
  final String phoneNumber;
  final String fullAddress;
  final String idType;
  final String? adminNotes;
  final DateTime createdAt;

  const Booking({
    required this.id,
    required this.productId,
    required this.productName,
    required this.productImage,
    required this.startDate,
    required this.endDate,
    required this.quantity,
    required this.dailyRateSnapshot,
    required this.refundableDepositSnapshot,
    required this.subtotal,
    required this.totalAmount,
    required this.status,
    required this.paymentStatus,
    required this.fullName,
    required this.phoneNumber,
    required this.fullAddress,
    required this.idType,
    this.adminNotes,
    required this.createdAt,
  });

  int get nights => endDate.difference(startDate).inDays + 1;

  bool get isPaid => paymentStatus == 'paid';

  /// Cancellable only before payment — once paid, a cancellation should go
  /// through a refund conversation with staff rather than a self-serve
  /// delete, since money has actually moved.
  bool get isCancellable => status == BookingStatus.pendingReview && !isPaid;

  /// Expects a row selected with:
  ///   *, products(name, product_images(storage_path, is_primary))
  /// (see BookingService.getMyBookings).
  factory Booking.fromRow(Map<String, dynamic> row, {String? resolvedImageUrl}) {
    final product = row['products'] as Map<String, dynamic>?;
    return Booking(
      id: row['id'] as String,
      productId: row['product_id'] as String,
      productName: product?['name'] as String? ?? 'Item',
      productImage: resolvedImageUrl ?? '',
      startDate: DateTime.parse(row['start_date'] as String),
      endDate: DateTime.parse(row['end_date'] as String),
      quantity: (row['quantity'] as num?)?.toInt() ?? 1,
      dailyRateSnapshot: (row['daily_rate_snapshot'] as num).toDouble(),
      refundableDepositSnapshot:
          (row['refundable_deposit_snapshot'] as num?)?.toDouble() ?? 0,
      subtotal: (row['subtotal'] as num).toDouble(),
      totalAmount: (row['total_amount'] as num).toDouble(),
      status: bookingStatusFromString(row['status'] as String? ?? 'pending_review'),
      paymentStatus: row['payment_status'] as String? ?? 'unpaid',
      fullName: row['full_name'] as String? ?? '',
      phoneNumber: row['phone_number'] as String? ?? '',
      fullAddress: row['full_address'] as String? ?? '',
      idType: row['id_type'] as String? ?? '',
      adminNotes: row['admin_notes'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}