// lib/services/booking_service.dart

import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/booking.dart';
import 'supabase_client.dart';

/// Handles the reservation flow: availability checks for a chosen date
/// range, uploading the ID photo / payment proof, creating the booking via
/// the `create_booking` RPC (see supabase/booking_schema.sql), and listing
/// the signed-in customer's bookings.
class BookingService {
  static const _bookingSelect = '''
    *,
    products(name, product_images(storage_path, is_primary))
  ''';

  /// Same RPC product_service.dart uses for the "today" snapshot, called
  /// here with the customer's chosen date range instead.
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

  /// Uploads into the private `booking-documents` bucket, under a folder
  /// named after the customer's own uid (required by the storage RLS
  /// policy). Returns the storage path (not a public URL — this bucket
  /// isn't public).
  static Future<String> _uploadDocument({
    required String subfolder,
    required Uint8List bytes,
    required String extension,
  }) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) throw StateError('Not signed in');
    final path =
        '$uid/$subfolder/${DateTime.now().microsecondsSinceEpoch}.$extension';
    await supabase.storage.from('booking-documents').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: false),
        );
    return path;
  }

  static Future<String> uploadIdPhoto(Uint8List bytes, String extension) =>
      _uploadDocument(subfolder: 'id-photos', bytes: bytes, extension: extension);

  /// Creates the booking (unpaid). Pricing is recomputed server-side by the
  /// RPC from the live product row, so nothing price-related is trusted
  /// from here. Call [createPaymongoCheckoutSession] right after to get a
  /// checkout URL for the customer to pay.
  static Future<Booking> createBooking({
    required String productId,
    required DateTime start,
    required DateTime end,
    required int quantity,
    required String fullName,
    required String phoneNumber,
    required String fullAddress,
    required String idType,
    required String idPhotoPath,
  }) async {
    final row = await supabase.rpc('create_booking', params: {
      'p_product_id': productId,
      'p_start_date': _dateOnly(start),
      'p_end_date': _dateOnly(end),
      'p_quantity': quantity,
      'p_full_name': fullName,
      'p_phone_number': phoneNumber,
      'p_full_address': fullAddress,
      'p_id_type': idType,
      'p_id_photo_path': idPhotoPath,
    });
    final data = row as Map<String, dynamic>;
    return Booking.fromRow(data);
  }

  /// Calls the create-paymongo-checkout-session Edge Function, which holds
  /// the PayMongo secret key server-side and returns a hosted checkout
  /// URL to open in the browser.
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

  /// Live updates for a single booking (used by the payment-pending screen
  /// to notice payment_status flip to 'paid' the moment the PayMongo
  /// webhook processes it — no polling needed).
  static Stream<Booking?> watchBooking(String bookingId) {
    return supabase
        .from('bookings')
        .stream(primaryKey: ['id'])
        .eq('id', bookingId)
        .map((rows) => rows.isEmpty ? null : Booking.fromRow(rows.first));
  }

  /// Used when the detail screen is opened without an `extra` Booking
  /// already in hand — e.g. a deep link straight to
  /// /account/bookings/:id rather than navigating from the list.
  static Future<Booking?> getBookingById(String id) async {
    final data = await supabase
        .from('bookings')
        .select(_bookingSelect)
        .eq('id', id)
        .maybeSingle();
    if (data == null) return null;

    final images = (data['products']?['product_images'] as List?) ?? [];
    String imageUrl = '';
    if (images.isNotEmpty) {
      final primary = images.firstWhere(
        (i) => i['is_primary'] == true,
        orElse: () => images.first,
      );
      final storagePath = primary['storage_path'] as String?;
      if (storagePath != null) {
        imageUrl = supabase.storage.from('product-images').getPublicUrl(storagePath);
      }
    }
    return Booking.fromRow(data, resolvedImageUrl: imageUrl);
  }

  static Future<List<Booking>> getMyBookings() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return [];

    final data = await supabase
        .from('bookings')
        .select(_bookingSelect)
        .eq('user_id', uid)
        .order('created_at', ascending: false);

    final rows = (data as List).cast<Map<String, dynamic>>();
    return rows.map((row) {
      final images = (row['products']?['product_images'] as List?) ?? [];
      String imageUrl = '';
      if (images.isNotEmpty) {
        final primary = images.firstWhere(
          (i) => i['is_primary'] == true,
          orElse: () => images.first,
        );
        final storagePath = primary['storage_path'] as String?;
        if (storagePath != null) {
          imageUrl = supabase.storage.from('product-images').getPublicUrl(storagePath);
        }
      }
      return Booking.fromRow(row, resolvedImageUrl: imageUrl);
    }).toList();
  }

  /// Only allowed by RLS while status is still 'pending_review'.
  static Future<void> cancelBooking(String bookingId) async {
    await supabase
        .from('bookings')
        .update({'status': 'cancelled'})
        .eq('id', bookingId);
  }

  static String _dateOnly(DateTime d) =>
      DateTime(d.year, d.month, d.day).toIso8601String().substring(0, 10);
}

/// Thrown/caught by the reservation wizard to show a readable message
/// instead of a raw PostgrestException string.
String describeBookingError(Object error) {
  if (error is PostgrestException) {
    return error.message;
  }
  return error.toString();
}