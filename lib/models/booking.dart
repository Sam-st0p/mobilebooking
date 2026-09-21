// lib/models/booking.dart
//
// Matches the REAL JSON contract returned by the backend's
// GET /api/mobile/account/bookings and /account/bookings/:id — which is
// just src/types/booking.ts's `Booking` interface, serialized as-is (see
// src/services/bookingService.ts on the Next.js side). The backend does
// all the Supabase joins/mapping; this only ever parses clean camelCase
// JSON, never raw Supabase rows.

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

String bookingStatusToApiValue(BookingStatus status) {
  switch (status) {
    case BookingStatus.draft:
      return 'draft';
    case BookingStatus.pending:
      return 'pending';
    case BookingStatus.approved:
      return 'approved';
    case BookingStatus.confirmed:
      return 'confirmed';
    case BookingStatus.readyForRelease:
      return 'ready_for_release';
    case BookingStatus.released:
      return 'released';
    case BookingStatus.returned:
      return 'returned';
    case BookingStatus.cancelled:
      return 'cancelled';
    case BookingStatus.rejected:
      return 'rejected';
  }
}

/// Mirrors the real `fulfillment_method` enum.
enum FulfillmentMethod { pickup, delivery }

FulfillmentMethod fulfillmentMethodFromString(String value) {
  return value == 'delivery' ? FulfillmentMethod.delivery : FulfillmentMethod.pickup;
}

/// One line item of a booking — mirrors `BookingItemLine` in booking.ts.
class BookingItem {
  final String bookingItemId;
  final String productId;
  final String productNameSnapshot;
  final String brand;
  final String category;
  final String imageUrl;
  final int quantity;
  final double dailyRateSnapshot;
  final double refundableDeposit;
  final List<String> included;
  final double lineRentalSubtotal;
  final int assignedUnitCount;

  const BookingItem({
    required this.bookingItemId,
    required this.productId,
    required this.productNameSnapshot,
    this.brand = '',
    this.category = '',
    this.imageUrl = '',
    required this.quantity,
    required this.dailyRateSnapshot,
    this.refundableDeposit = 0,
    this.included = const [],
    this.lineRentalSubtotal = 0,
    this.assignedUnitCount = 0,
  });

  factory BookingItem.fromJson(Map<String, dynamic> json) {
    return BookingItem(
      bookingItemId: json['bookingItemId'] as String? ?? '',
      productId: json['productId'] as String? ?? '',
      productNameSnapshot: json['productName'] as String? ?? 'Item',
      brand: json['brand'] as String? ?? '',
      category: json['category'] as String? ?? '',
      imageUrl: json['image'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      dailyRateSnapshot: (json['dailyRate'] as num?)?.toDouble() ?? 0,
      refundableDeposit: (json['refundableDeposit'] as num?)?.toDouble() ?? 0,
      included: ((json['included'] as List?) ?? []).map((e) => e.toString()).toList(),
      lineRentalSubtotal: (json['lineRentalSubtotal'] as num?)?.toDouble() ?? 0,
      assignedUnitCount: (json['assignedUnitCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Mirrors `BookingProductSnapshot`.
class BookingProductSnapshot {
  final String name;
  final String brand;
  final String category;
  final String image;
  final double pricePerDay;
  final String currency;
  final List<String> included;
  final String? color;

  const BookingProductSnapshot({
    required this.name,
    this.brand = '',
    this.category = '',
    this.image = '',
    this.pricePerDay = 0,
    this.currency = 'PHP',
    this.included = const [],
    this.color,
  });

  factory BookingProductSnapshot.fromJson(Map<String, dynamic> json) {
    return BookingProductSnapshot(
      name: json['name'] as String? ?? 'Item',
      brand: json['brand'] as String? ?? '',
      category: json['category'] as String? ?? '',
      image: json['image'] as String? ?? '',
      pricePerDay: (json['pricePerDay'] as num?)?.toDouble() ?? 0,
      currency: json['currency'] as String? ?? 'PHP',
      included: ((json['included'] as List?) ?? []).map((e) => e.toString()).toList(),
      color: json['color'] as String?,
    );
  }
}

class Booking {
  final String id;
  final String bookingReference; // bookingRef in the JSON
  final String customerId;
  final bool isGuestCheckout;
  final List<BookingItem> items;
  final int quantity;
  final BookingStatus status;
  final FulfillmentMethod fulfillmentMethod;
  final DateTime pickupAt; // startDate in the JSON
  final DateTime returnAt; // endDate in the JSON
  final DateTime? nextAvailableAt;
  final int dayCount;
  final double dailyRate;
  final double refundableDeposit;
  final double rentalSubtotal;
  final double specialDiscountAmount;
  final double birthdayDiscountAmount;
  final String birthdayDiscountStatus;
  final int loyaltyCompletedRentalsSnapshot;
  final double loyaltyDiscountAmount;
  final String loyaltyDiscountStatus;
  final double deliveryFee;
  final double? pickupConvenienceFee;
  final double totalAmount;
  final String balancePaymentPreference;
  final bool payLaterAllowed;
  final String? location;
  final String? customerNotes;
  final String? adminNotes;
  final BookingProductSnapshot productSnapshot;
  final String requirementsStatus; // "not_submitted" | "pending_review" | "approved" | "rejected"
  final String agreementStatus;
  final DateTime? approvedAt;
  final DateTime? confirmedAt;
  final DateTime? rejectedAt;
  final DateTime? readyForReleaseAt;
  final DateTime? releasedAt;
  final DateTime? returnedAt;
  final DateTime? cancelledAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Booking({
    required this.id,
    required this.bookingReference,
    required this.customerId,
    this.isGuestCheckout = false,
    this.items = const [],
    this.quantity = 1,
    required this.status,
    required this.fulfillmentMethod,
    required this.pickupAt,
    required this.returnAt,
    this.nextAvailableAt,
    required this.dayCount,
    required this.dailyRate,
    this.refundableDeposit = 0,
    this.rentalSubtotal = 0,
    this.specialDiscountAmount = 0,
    this.birthdayDiscountAmount = 0,
    this.birthdayDiscountStatus = 'not_eligible',
    this.loyaltyCompletedRentalsSnapshot = 0,
    this.loyaltyDiscountAmount = 0,
    this.loyaltyDiscountStatus = 'not_eligible',
    this.deliveryFee = 0,
    this.pickupConvenienceFee,
    required this.totalAmount,
    this.balancePaymentPreference = 'in_person',
    this.payLaterAllowed = false,
    this.location,
    this.customerNotes,
    this.adminNotes,
    required this.productSnapshot,
    this.requirementsStatus = 'not_submitted',
    this.agreementStatus = 'not_created',
    this.approvedAt,
    this.confirmedAt,
    this.rejectedAt,
    this.readyForReleaseAt,
    this.releasedAt,
    this.returnedAt,
    this.cancelledAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Booking.fromJson(Map<String, dynamic> json) {
    DateTime? parseOpt(String? key) => json[key] != null ? DateTime.parse(json[key] as String) : null;

    // A booking with a missing/odd date must not be able to break the whole list
    // (older or half-created rows can have empty pickup/return timestamps).
    DateTime? tryDate(dynamic v) => v is String ? DateTime.tryParse(v) : null;
    final createdAtValue = tryDate(json['createdAt']) ?? DateTime.now();
    final startAtValue = tryDate(json['startDate']) ?? createdAtValue;
    final dayCountValue = (json['dayCount'] as num?)?.toInt() ?? 0;

    return Booking(
      id: json['id'] as String,
      bookingReference: json['bookingRef'] as String? ?? '',
      customerId: json['customerId'] as String? ?? '',
      isGuestCheckout: json['isGuestCheckout'] as bool? ?? false,
      items: ((json['items'] as List?) ?? []).map((r) => BookingItem.fromJson(r as Map<String, dynamic>)).toList(),
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      status: bookingStatusFromString(json['status'] as String? ?? 'pending'),
      fulfillmentMethod: fulfillmentMethodFromString(json['fulfillmentMethod'] as String? ?? 'pickup'),
      pickupAt: startAtValue,
      returnAt: tryDate(json['endDate']) ?? startAtValue.add(Duration(days: dayCountValue > 0 ? dayCountValue : 1)),
      nextAvailableAt: parseOpt('nextAvailableAt'),
      dayCount: (json['dayCount'] as num?)?.toInt() ?? 0,
      dailyRate: (json['dailyRate'] as num?)?.toDouble() ?? 0,
      refundableDeposit: (json['refundableDeposit'] as num?)?.toDouble() ?? 0,
      rentalSubtotal: (json['rentalSubtotal'] as num?)?.toDouble() ?? 0,
      specialDiscountAmount: (json['specialDiscountAmount'] as num?)?.toDouble() ?? 0,
      birthdayDiscountAmount: (json['birthdayDiscountAmount'] as num?)?.toDouble() ?? 0,
      birthdayDiscountStatus: json['birthdayDiscountStatus'] as String? ?? 'not_eligible',
      loyaltyCompletedRentalsSnapshot: (json['loyaltyCompletedRentalsSnapshot'] as num?)?.toInt() ?? 0,
      loyaltyDiscountAmount: (json['loyaltyDiscountAmount'] as num?)?.toDouble() ?? 0,
      loyaltyDiscountStatus: json['loyaltyDiscountStatus'] as String? ?? 'not_eligible',
      deliveryFee: (json['deliveryFee'] as num?)?.toDouble() ?? 0,
      pickupConvenienceFee: (json['pickupConvenienceFee'] as num?)?.toDouble(),
      totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0,
      balancePaymentPreference: json['balancePaymentPreference'] as String? ?? 'in_person',
      payLaterAllowed: json['payLaterAllowed'] as bool? ?? false,
      location: json['location'] as String?,
      customerNotes: json['customerNotes'] as String?,
      adminNotes: json['adminNotes'] as String?,
      productSnapshot: BookingProductSnapshot.fromJson(
        (json['productSnapshot'] as Map<String, dynamic>?) ?? const {},
      ),
      requirementsStatus: json['requirementsStatus'] as String? ?? 'not_submitted',
      agreementStatus: json['agreementStatus'] as String? ?? 'not_created',
      approvedAt: parseOpt('approvedAt'),
      confirmedAt: parseOpt('confirmedAt'),
      rejectedAt: parseOpt('rejectedAt'),
      readyForReleaseAt: parseOpt('readyForReleaseAt'),
      releasedAt: parseOpt('releasedAt'),
      returnedAt: parseOpt('returnedAt'),
      cancelledAt: parseOpt('cancelledAt'),
      createdAt: createdAtValue,
      updatedAt: tryDate(json['updatedAt']) ?? createdAtValue,
    );
  }

  // ---- Convenience getters used by the UI screens ----

  String get primaryProductName =>
      items.isEmpty ? productSnapshot.name : (items.length == 1 ? items.first.productNameSnapshot : '${items.first.productNameSnapshot} +${items.length - 1} more');

  String get primaryImageUrl => items.isNotEmpty ? items.first.imageUrl : productSnapshot.image;

  int get totalQuantity => items.isEmpty ? quantity : items.fold(0, (sum, i) => sum + i.quantity);

  int get nights => dayCount;

  /// NOTE: payment status isn't in this contract yet — it lives in
  /// `booking_payment_submissions`, which the backend doesn't expose via
  /// GET /account/bookings yet (see paymentService.ts / mobile payments
  /// route for the closest equivalent, keyed by booking). Treat this as a
  /// placeholder until a real "latest payment status per booking" field is
  /// added to the backend response — do not rely on it for gating UI.
  bool get isPaid => status == BookingStatus.confirmed ||
      status == BookingStatus.readyForRelease ||
      status == BookingStatus.released ||
      status == BookingStatus.returned;

  bool get isCancellable => status == BookingStatus.pending || status == BookingStatus.approved;
}