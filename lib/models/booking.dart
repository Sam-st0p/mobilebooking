// lib/models/booking.dart
//
// Rebuilt against the REAL Supabase schema (see database.types.ts), not the
// invented one this was originally written against. Key differences from
// the old model:
//   - No more full_name/phone_number/full_address/id_type/payment_status
//     columns on `bookings` — identity/ID docs now live in
//     `booking_requirements` (+ `customer_documents`), and payment state
//     lives in `booking_payment_submissions`. Both are separate rebuild
//     stages; until then, isPaid/requirements info is not available here.
//   - `bookings` is now a header row; line items live in `booking_items`,
//     fulfillment (pickup/delivery) in `booking_fulfillments`, and computed
//     money fields in the `booking_totals` VIEW (fetched separately below,
//     since views aren't reliably embeddable via PostgREST FK inference).

/// Mirrors the real `booking_status` enum.
enum BookingStatus {
  draft,
  pending,
  approved,
  confirmed,
  readyForRelease,
  released,
  returned,
  cancelled,
  rejected,
}

BookingStatus bookingStatusFromString(String value) {
  switch (value) {
    case 'draft':
      return BookingStatus.draft;
    case 'pending':
      return BookingStatus.pending;
    case 'approved':
      return BookingStatus.approved;
    case 'confirmed':
      return BookingStatus.confirmed;
    case 'ready_for_release':
      return BookingStatus.readyForRelease;
    case 'released':
      return BookingStatus.released;
    case 'returned':
      return BookingStatus.returned;
    case 'cancelled':
      return BookingStatus.cancelled;
    case 'rejected':
      return BookingStatus.rejected;
    default:
      return BookingStatus.pending;
  }
}

String bookingStatusLabel(BookingStatus status) {
  switch (status) {
    case BookingStatus.draft:
      return 'Draft';
    case BookingStatus.pending:
      return 'Pending Review';
    case BookingStatus.approved:
      return 'Approved';
    case BookingStatus.confirmed:
      return 'Confirmed';
    case BookingStatus.readyForRelease:
      return 'Ready for Release';
    case BookingStatus.released:
      return 'Released';
    case BookingStatus.returned:
      return 'Returned';
    case BookingStatus.cancelled:
      return 'Cancelled';
    case BookingStatus.rejected:
      return 'Rejected';
  }
}

/// Mirrors the real `fulfillment_method` enum.
enum FulfillmentMethod { pickup, delivery }

FulfillmentMethod fulfillmentMethodFromString(String value) {
  return value == 'delivery' ? FulfillmentMethod.delivery : FulfillmentMethod.pickup;
}

class BookingItem {
  final String id;
  final String productId;
  final String productNameSnapshot;
  final double dailyRateSnapshot;
  final double depositPerUnitSnapshot;
  final int quantity;
  final String imageUrl;

  const BookingItem({
    required this.id,
    required this.productId,
    required this.productNameSnapshot,
    required this.dailyRateSnapshot,
    required this.depositPerUnitSnapshot,
    required this.quantity,
    this.imageUrl = '',
  });

  /// Expects a row selected with:
  ///   booking_items(id, product_id, product_name_snapshot,
  ///     daily_rate_snapshot, deposit_per_unit_snapshot, quantity,
  ///     products(product_images(storage_path, is_primary)))
  factory BookingItem.fromRow(Map<String, dynamic> row) {
    String imageUrl = '';
    final product = row['products'] as Map<String, dynamic>?;
    final images = (product?['product_images'] as List?) ?? [];
    if (images.isNotEmpty) {
      final primary = images.firstWhere(
        (i) => i['is_primary'] == true,
        orElse: () => images.first,
      ) as Map<String, dynamic>;
      final storagePath = primary['storage_path'] as String?;
      if (storagePath != null) {
        // Resolved by the caller (BookingService), which has access to the
        // supabase client's storage bucket helper. Left blank here and
        // filled in by BookingService.getMyBookings/getBookingById.
        imageUrl = storagePath;
      }
    }
    return BookingItem(
      id: row['id'] as String,
      productId: row['product_id'] as String,
      productNameSnapshot: row['product_name_snapshot'] as String? ?? 'Item',
      dailyRateSnapshot: (row['daily_rate_snapshot'] as num).toDouble(),
      depositPerUnitSnapshot: (row['deposit_per_unit_snapshot'] as num?)?.toDouble() ?? 0,
      quantity: (row['quantity'] as num?)?.toInt() ?? 1,
      imageUrl: imageUrl,
    );
  }

  BookingItem withResolvedImageUrl(String url) => BookingItem(
        id: id,
        productId: productId,
        productNameSnapshot: productNameSnapshot,
        dailyRateSnapshot: dailyRateSnapshot,
        depositPerUnitSnapshot: depositPerUnitSnapshot,
        quantity: quantity,
        imageUrl: url,
      );
}

class BookingFulfillment {
  final FulfillmentMethod method;
  final String? addressLine1;
  final String? addressLine2;
  final String? barangay;
  final String? cityMunicipality;
  final String? province;
  final String? postalCode;
  final String? recipientName;
  final String? contactNumber;
  final String? deliveryNotes;
  final double deliveryFeeSnapshot;
  final double pickupConvenienceFeeSnapshot;
  final DateTime? scheduledAt;
  final DateTime? completedAt;

  const BookingFulfillment({
    required this.method,
    this.addressLine1,
    this.addressLine2,
    this.barangay,
    this.cityMunicipality,
    this.province,
    this.postalCode,
    this.recipientName,
    this.contactNumber,
    this.deliveryNotes,
    this.deliveryFeeSnapshot = 0,
    this.pickupConvenienceFeeSnapshot = 0,
    this.scheduledAt,
    this.completedAt,
  });

  factory BookingFulfillment.fromRow(Map<String, dynamic> row) {
    return BookingFulfillment(
      method: fulfillmentMethodFromString(row['method'] as String? ?? 'pickup'),
      addressLine1: row['address_line_1'] as String?,
      addressLine2: row['address_line_2'] as String?,
      barangay: row['barangay'] as String?,
      cityMunicipality: row['city_municipality'] as String?,
      province: row['province'] as String?,
      postalCode: row['postal_code'] as String?,
      recipientName: row['recipient_name'] as String?,
      contactNumber: row['contact_number'] as String?,
      deliveryNotes: row['delivery_notes'] as String?,
      deliveryFeeSnapshot: (row['delivery_fee_snapshot'] as num?)?.toDouble() ?? 0,
      pickupConvenienceFeeSnapshot:
          (row['pickup_convenience_fee_snapshot'] as num?)?.toDouble() ?? 0,
      scheduledAt: row['scheduled_at'] != null ? DateTime.parse(row['scheduled_at'] as String) : null,
      completedAt: row['completed_at'] != null ? DateTime.parse(row['completed_at'] as String) : null,
    );
  }
}

/// Mirrors the `booking_totals` VIEW. Fetched separately from the booking
/// header (see BookingService) since PostgREST can't reliably embed a view
/// via FK inference the way it embeds real tables.
class BookingTotals {
  final int rentalDays;
  final double rentalSubtotal;
  final double depositTotal;
  final double deliveryFee;
  final double pickupConvenienceFee;
  final double specialDiscountTotal;
  final double totalAmount;

  const BookingTotals({
    required this.rentalDays,
    required this.rentalSubtotal,
    required this.depositTotal,
    required this.deliveryFee,
    required this.pickupConvenienceFee,
    required this.specialDiscountTotal,
    required this.totalAmount,
  });

  factory BookingTotals.fromRow(Map<String, dynamic> row) {
    return BookingTotals(
      rentalDays: (row['rental_days'] as num?)?.toInt() ?? 0,
      rentalSubtotal: (row['rental_subtotal'] as num?)?.toDouble() ?? 0,
      depositTotal: (row['deposit_total'] as num?)?.toDouble() ?? 0,
      deliveryFee: (row['delivery_fee'] as num?)?.toDouble() ?? 0,
      pickupConvenienceFee: (row['pickup_convenience_fee'] as num?)?.toDouble() ?? 0,
      specialDiscountTotal: (row['special_discount_total'] as num?)?.toDouble() ?? 0,
      totalAmount: (row['total_amount'] as num?)?.toDouble() ?? 0,
    );
  }
}

class Booking {
  final String id;
  final String bookingReference;
  final BookingStatus status;
  final String customerId;
  final String? customerNotes;
  final String? adminNotes;
  final String currencyCode;

  final DateTime pickupAt;
  final DateTime returnAt;
  final DateTime? nextAvailableAt;

  final DateTime? approvedAt;
  final DateTime? confirmedAt;
  final DateTime? rejectedAt;
  final DateTime? readyForReleaseAt;
  final DateTime? releasedAt;
  final DateTime? returnedAt;
  final DateTime? cancelledAt;

  final double birthdayDiscountAmount;
  final String birthdayDiscountStatus;
  final double loyaltyDiscountAmount;
  final String loyaltyDiscountStatus;
  final int loyaltyCompletedRentalsSnapshot;

  final DateTime createdAt;
  final DateTime updatedAt;

  final List<BookingItem> items;
  final BookingFulfillment? fulfillment;
  final BookingTotals? totals;

  // NOTE: Payment status is intentionally NOT modeled here. It now lives in
  // `booking_payment_submissions` (a booking can have several payment
  // attempts across down_payment/balance stages). Once the payment rebuild
  // (stage 5) lands, BookingService will expose a way to fetch the latest
  // relevant submission per booking; surface that in the UI rather than a
  // single boolean.

  const Booking({
    required this.id,
    required this.bookingReference,
    required this.status,
    required this.customerId,
    this.customerNotes,
    this.adminNotes,
    required this.currencyCode,
    required this.pickupAt,
    required this.returnAt,
    this.nextAvailableAt,
    this.approvedAt,
    this.confirmedAt,
    this.rejectedAt,
    this.readyForReleaseAt,
    this.releasedAt,
    this.returnedAt,
    this.cancelledAt,
    this.birthdayDiscountAmount = 0,
    this.birthdayDiscountStatus = 'none',
    this.loyaltyDiscountAmount = 0,
    this.loyaltyDiscountStatus = 'none',
    this.loyaltyCompletedRentalsSnapshot = 0,
    required this.createdAt,
    required this.updatedAt,
    this.items = const [],
    this.fulfillment,
    this.totals,
  });

  /// Best-effort display name for list/detail screens when there are
  /// multiple line items — most bookings will have exactly one.
  String get primaryProductName =>
      items.isEmpty ? 'Booking' : items.length == 1 ? items.first.productNameSnapshot : '${items.first.productNameSnapshot} +${items.length - 1} more';

  String get primaryImageUrl => items.isEmpty ? '' : items.first.imageUrl;

  int get totalQuantity => items.fold(0, (sum, i) => sum + i.quantity);

  int get nights => totals?.rentalDays ?? returnAt.difference(pickupAt).inDays;

  double get totalAmount => totals?.totalAmount ?? 0;

  /// Matches `cancel_own_booking` RPC's allowed states (self-service
  /// cancellation while pending or approved — not yet paid/fulfilled).
  bool get isCancellable => status == BookingStatus.pending || status == BookingStatus.approved;

  /// Expects a row selected with:
  ///   *,
  ///   booking_items(id, product_id, product_name_snapshot,
  ///     daily_rate_snapshot, deposit_per_unit_snapshot, quantity,
  ///     products(product_images(storage_path, is_primary))),
  ///   booking_fulfillments(*)
  /// (see BookingService._bookingSelect). `totals` is attached afterward by
  /// the service, since it comes from a separate `booking_totals` query.
  factory Booking.fromRow(Map<String, dynamic> row, {BookingTotals? totals}) {
    final itemRows = (row['booking_items'] as List?) ?? [];
    final fulfillmentRow = row['booking_fulfillments'];

    return Booking(
      id: row['id'] as String,
      bookingReference: row['booking_reference'] as String? ?? '',
      status: bookingStatusFromString(row['status'] as String? ?? 'pending'),
      customerId: row['customer_id'] as String,
      customerNotes: row['customer_notes'] as String?,
      adminNotes: row['admin_notes'] as String?,
      currencyCode: row['currency_code'] as String? ?? 'PHP',
      pickupAt: DateTime.parse(row['pickup_at'] as String),
      returnAt: DateTime.parse(row['return_at'] as String),
      nextAvailableAt:
          row['next_available_at'] != null ? DateTime.parse(row['next_available_at'] as String) : null,
      approvedAt: row['approved_at'] != null ? DateTime.parse(row['approved_at'] as String) : null,
      confirmedAt: row['confirmed_at'] != null ? DateTime.parse(row['confirmed_at'] as String) : null,
      rejectedAt: row['rejected_at'] != null ? DateTime.parse(row['rejected_at'] as String) : null,
      readyForReleaseAt: row['ready_for_release_at'] != null
          ? DateTime.parse(row['ready_for_release_at'] as String)
          : null,
      releasedAt: row['released_at'] != null ? DateTime.parse(row['released_at'] as String) : null,
      returnedAt: row['returned_at'] != null ? DateTime.parse(row['returned_at'] as String) : null,
      cancelledAt: row['cancelled_at'] != null ? DateTime.parse(row['cancelled_at'] as String) : null,
      birthdayDiscountAmount: (row['birthday_discount_amount'] as num?)?.toDouble() ?? 0,
      birthdayDiscountStatus: row['birthday_discount_status'] as String? ?? 'none',
      loyaltyDiscountAmount: (row['loyalty_discount_amount'] as num?)?.toDouble() ?? 0,
      loyaltyDiscountStatus: row['loyalty_discount_status'] as String? ?? 'none',
      loyaltyCompletedRentalsSnapshot:
          (row['loyalty_completed_rentals_snapshot'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      items: itemRows.map((r) => BookingItem.fromRow(r as Map<String, dynamic>)).toList(),
      fulfillment: fulfillmentRow is Map<String, dynamic> ? BookingFulfillment.fromRow(fulfillmentRow) : null,
      totals: totals,
    );
  }

  Booking withTotals(BookingTotals? t) => Booking(
        id: id,
        bookingReference: bookingReference,
        status: status,
        customerId: customerId,
        customerNotes: customerNotes,
        adminNotes: adminNotes,
        currencyCode: currencyCode,
        pickupAt: pickupAt,
        returnAt: returnAt,
        nextAvailableAt: nextAvailableAt,
        approvedAt: approvedAt,
        confirmedAt: confirmedAt,
        rejectedAt: rejectedAt,
        readyForReleaseAt: readyForReleaseAt,
        releasedAt: releasedAt,
        returnedAt: returnedAt,
        cancelledAt: cancelledAt,
        birthdayDiscountAmount: birthdayDiscountAmount,
        birthdayDiscountStatus: birthdayDiscountStatus,
        loyaltyDiscountAmount: loyaltyDiscountAmount,
        loyaltyDiscountStatus: loyaltyDiscountStatus,
        loyaltyCompletedRentalsSnapshot: loyaltyCompletedRentalsSnapshot,
        createdAt: createdAt,
        updatedAt: updatedAt,
        items: items,
        fulfillment: fulfillment,
        totals: t,
      );

  Booking withItems(List<BookingItem> newItems) => Booking(
        id: id,
        bookingReference: bookingReference,
        status: status,
        customerId: customerId,
        customerNotes: customerNotes,
        adminNotes: adminNotes,
        currencyCode: currencyCode,
        pickupAt: pickupAt,
        returnAt: returnAt,
        nextAvailableAt: nextAvailableAt,
        approvedAt: approvedAt,
        confirmedAt: confirmedAt,
        rejectedAt: rejectedAt,
        readyForReleaseAt: readyForReleaseAt,
        releasedAt: releasedAt,
        returnedAt: returnedAt,
        cancelledAt: cancelledAt,
        birthdayDiscountAmount: birthdayDiscountAmount,
        birthdayDiscountStatus: birthdayDiscountStatus,
        loyaltyDiscountAmount: loyaltyDiscountAmount,
        loyaltyDiscountStatus: loyaltyDiscountStatus,
        loyaltyCompletedRentalsSnapshot: loyaltyCompletedRentalsSnapshot,
        createdAt: createdAt,
        updatedAt: updatedAt,
        items: newItems,
        fulfillment: fulfillment,
        totals: totals,
      );
}