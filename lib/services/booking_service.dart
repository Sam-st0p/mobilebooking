// lib/services/booking_service.dart
//
// Rebuilt against the REAL schema/RPCs (see database.types.ts), replacing
// the version built against the invented 9-param create_booking + flat
// bookings.products relationship. Key differences:
//   - `bookings` has NO direct FK to `products` — products are reached via
//     bookings -> booking_items -> products. Fixes the PGRST200 error.
//   - `create_booking` is now a 14-param RPC using rental_start/end_date,
//     fulfillment_method/location/city/province, and jsonb product/customer
//     snapshots — NOT the old p_full_name/p_id_type/etc. Fixes the 404
//     "function not found" error (PostgREST matches RPCs by exact param
//     signature, so the old call could never have worked against this DB).
//   - Cancellation now goes through the `cancel_own_booking` RPC (matches
//     real RLS/business rules — e.g. only allowed while pending/approved)
//     rather than a raw `update`.
//   - `booking_totals` is a VIEW, fetched separately per booking id(s) and
//     attached in Dart, since PostgREST can't reliably embed views the way
//     it embeds real FK-linked tables.
//
// STILL OPEN (do not guess — confirm before relying on this in production):
//   - Exact keys expected inside p_product_snapshot / p_customer_snapshot.
//     Not visible in database.types.ts (that only gives you the RPC's
//     scalar/jsonb *parameter* names, not what the function body reads out
//     of the jsonb). Mirror src/services/bookingService.ts's snapshot
//     builders from the website repo once available.
//   - Real avatar/product-image storage bucket name is assumed
//     'product-images' here (carried over from the old code, unconfirmed).

import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/booking.dart';
import 'supabase_client.dart';

class BookingService {
  /// booking_fulfillments is a true 1:1 (unique FK), so PostgREST returns
  /// it as a single object, not a list. booking_items is a normal to-many.
  static const _bookingSelect = '''
    *,
    booking_items(
      id, product_id, product_name_snapshot, daily_rate_snapshot,
      deposit_per_unit_snapshot, quantity,
      products(product_images(storage_path, is_primary))
    ),
    booking_fulfillments(*)
  ''';

  /// Unchanged — get_product_availability's signature didn't change in the
  /// real schema.
  static Future<({int totalUnits, int availableUnits})> checkAvailability(
    String productId,
    DateTime start,
    DateTime end,
  ) async {
    final data = await supabase.rpc('get_product_availability', params: {
      'p_product_id': productId,
      'p_start_date': _dateOnly(start),
      'p_end_date': _dateOnly(end),
    });
    final rows = (data as List?) ?? [];
    if (rows.isEmpty) return (totalUnits: 0, availableUnits: 0);
    final row = rows.first as Map<String, dynamic>;
    return (
      totalUnits: (row['total_units'] as num?)?.toInt() ?? 0,
      availableUnits: (row['available_units'] as num?)?.toInt() ?? 0,
    );
  }

  /// Uploads into `customer_documents`' backing storage bucket. Bucket name
  /// carried over from the old code as an assumption — confirm the real
  /// bucket name (booking_requirements work, stage 3, will need this too).
  static Future<String> _uploadDocument({
    required String subfolder,
    required Uint8List bytes,
    required String extension,
  }) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) throw StateError('Not signed in');
    final path = '$uid/$subfolder/${DateTime.now().microsecondsSinceEpoch}.$extension';
    await supabase.storage.from('booking-documents').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: false),
        );
    return path;
  }

  static Future<String> uploadIdPhoto(Uint8List bytes, String extension) =>
      _uploadDocument(subfolder: 'id-photos', bytes: bytes, extension: extension);

  /// Resolves a `product_images.storage_path` into a public URL. Bucket
  /// name assumed 'product-images' (unconfirmed, carried over from old
  /// code — flag if wrong, it's a one-line fix).
  static String _resolveImageUrl(String storagePath) =>
      supabase.storage.from('product-images').getPublicUrl(storagePath);

  static Booking _attachResolvedImages(Booking booking) {
    final items = booking.items
        .map((item) => item.imageUrl.isEmpty
            ? item
            : item.withResolvedImageUrl(_resolveImageUrl(item.imageUrl)))
        .toList();
    return booking.withItems(items);
  }

  /// Creates the booking (status starts 'pending' — admin must approve
  /// before payment/requirements/agreement can proceed). Pricing is
  /// recomputed server-side by the RPC; nothing price-related is trusted
  /// from the client.
  ///
  /// [productSnapshot] / [customerSnapshot]: pass pre-built maps. Their
  /// exact expected shape is NOT yet confirmed (see file header) — do not
  /// invent keys here; get them from the website's bookingService.ts or
  /// the create_booking function body once available.
  static Future<Booking> createBooking({
    required String productId,
    required DateTime rentalStartDate,
    required DateTime rentalEndDate,
    required String fulfillmentMethod, // 'pickup' | 'delivery'
    required String location,
    required String customerNotes,
    required double deliveryFee,
    required double discountAmount,
    required Map<String, dynamic> productSnapshot,
    required Map<String, dynamic> customerSnapshot,
    int quantity = 1,
    String? cityMunicipality,
    String? province,
    Map<String, dynamic>? emergencyContact,
  }) async {
    final row = await supabase.rpc('create_booking', params: {
      'p_product_id': productId,
      'p_rental_start_date': _dateOnly(rentalStartDate),
      'p_rental_end_date': _dateOnly(rentalEndDate),
      'p_fulfillment_method': fulfillmentMethod,
      'p_location': location,
      'p_customer_notes': customerNotes,
      'p_delivery_fee': deliveryFee,
      'p_discount_amount': discountAmount,
      'p_product_snapshot': productSnapshot,
      'p_customer_snapshot': customerSnapshot,
      'p_quantity': quantity,
      if (cityMunicipality != null) 'p_city_municipality': cityMunicipality,
      if (province != null) 'p_province': province,
      if (emergencyContact != null) 'p_emergency_contact': emergencyContact,
    });
    // The RPC returns the bookings row only (no nested items/fulfillment
    // yet on this exact response) — re-fetch the full shape so the caller
    // gets a fully-populated Booking consistent with getMyBookings/
    // getBookingById.
    final created = row as Map<String, dynamic>;
    final full = await getBookingById(created['id'] as String);
    return full ?? Booking.fromRow(created);
  }

  /// Calls the mobile-specific create-paymongo-checkout-session Edge
  /// Function. NOTE: this Edge Function still targets the OLD
  /// bookings.payment_status shape internally and needs to be rebuilt
  /// against booking_payment_submissions (stage 5) before this will work
  /// end-to-end — the client-side call shape here won't need to change,
  /// but don't expect a working checkout URL until that stage lands.
  static Future<String> createPaymongoCheckoutSession(String bookingId) async {
    final res = await supabase.functions.invoke(
      'create-paymongo-checkout-session',
      body: {'booking_id': bookingId},
    );
    final data = res.data;
    if (data is! Map || data['checkout_url'] == null) {
      throw StateError((data is Map ? data['error'] : null) ?? 'Could not start payment.');
    }
    return data['checkout_url'] as String;
  }

  /// Live updates for a single booking's header row (status changes etc).
  /// Realtime `.stream()` only ever gives flat table rows — no nested
  /// items/fulfillment/totals. Callers that need the full shape after a
  /// change should re-fetch via getBookingById.
  static Stream<Map<String, dynamic>?> watchBookingStatus(String bookingId) {
    return supabase
        .from('bookings')
        .stream(primaryKey: ['id'])
        .eq('id', bookingId)
        .map((rows) => rows.isEmpty ? null : rows.first);
  }

  static Future<Booking?> getBookingById(String id) async {
    final data = await supabase.from('bookings').select(_bookingSelect).eq('id', id).maybeSingle();
    if (data == null) return null;

    final totalsRow =
        await supabase.from('booking_totals').select('*').eq('booking_id', id).maybeSingle();
    final totals = totalsRow != null ? BookingTotals.fromRow(totalsRow) : null;

    return _attachResolvedImages(Booking.fromRow(data, totals: totals));
  }

  static Future<List<Booking>> getMyBookings() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return [];

    final data = await supabase
        .from('bookings')
        .select(_bookingSelect)
        .eq('customer_id', uid)
        .order('created_at', ascending: false);

    final rows = (data as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return [];

    final ids = rows.map((r) => r['id'] as String).toList();
    final totalsRows = await supabase.from('booking_totals').select('*').inFilter('booking_id', ids);
    final totalsById = {
      for (final t in (totalsRows as List).cast<Map<String, dynamic>>())
        t['booking_id'] as String: BookingTotals.fromRow(t),
    };

    return rows
        .map((row) => _attachResolvedImages(
              Booking.fromRow(row, totals: totalsById[row['id'] as String]),
            ))
        .toList();
  }

  /// Uses the real cancel_own_booking RPC (enforces the same "only while
  /// pending/approved" rule server-side that Booking.isCancellable mirrors
  /// client-side for UI purposes).
  static Future<void> cancelBooking(String bookingId, {String? note}) async {
    await supabase.rpc('cancel_own_booking', params: {
      'p_booking_id': bookingId,
      if (note != null) 'p_note': note,
    });
  }

  static String _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day).toIso8601String().substring(0, 10);
}

/// Thrown/caught by the reservation wizard to show a readable message
/// instead of a raw PostgrestException string.
String describeBookingError(Object error) {
  if (error is PostgrestException) {
    return error.message;
  }
  return error.toString();
}