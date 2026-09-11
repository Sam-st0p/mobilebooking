// lib/services/booking_service.dart
//
// Calls the backend's /api/mobile/bookings* and /api/mobile/catalog/:id/
// availability-check routes. Everything returns typed models (Booking),
// not raw maps — the backend does the Supabase work and hands back clean
// JSON matching src/types/booking.ts.

import 'dart:async';
import 'package:dio/dio.dart';
import '../models/booking.dart';
import 'api_client.dart';

class AvailabilityCheckResult {
  final int totalUnits;
  final int availableUnits;
  const AvailabilityCheckResult({required this.totalUnits, required this.availableUnits});
}

/// Human-readable message for any error thrown by BookingService/
/// ProductService/etc. — screens call this instead of showing e.toString().
String describeBookingError(Object error) {
  if (error is Exception) {
    final message = error.toString().replaceFirst('Exception: ', '');
    if (message.isNotEmpty) return message;
  }
  return 'Something went wrong. Please try again.';
}

class BookingService {
  static Dio get _dio => ApiClient.instance.dio;

  static Future<List<Booking>> getMyBookings() async {
    try {
      final response = await _dio.get('/api/mobile/account/bookings');
      final data = response.data as Map<String, dynamic>;
      final rows = (data['bookings'] as List).cast<Map<String, dynamic>>();
      return rows.map(Booking.fromJson).toList();
    } catch (e) {
      throw Exception(apiErrorMessage(e, fallback: 'Could not load your bookings.'));
    }
  }

  static Future<Booking?> getBookingById(String id) async {
    try {
      final response = await _dio.get('/api/mobile/account/bookings/$id');
      final data = response.data as Map<String, dynamic>;
      return Booking.fromJson(data['booking'] as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw Exception(apiErrorMessage(e, fallback: 'Could not load this booking.'));
    }
  }

  static Future<Booking> cancelBooking(String id, {String? note}) async {
    try {
      final response = await _dio.post(
        '/api/mobile/account/bookings/$id/cancel',
        data: {if (note != null) 'note': note},
      );
      final data = response.data as Map<String, dynamic>;
      return Booking.fromJson(data['booking'] as Map<String, dynamic>);
    } catch (e) {
      throw Exception(apiErrorMessage(e, fallback: 'Could not cancel this booking.'));
    }
  }

  static Future<List<Map<String, dynamic>>> getMyPayments() async {
    try {
      final response = await _dio.get('/api/mobile/account/payments');
      final data = response.data as Map<String, dynamic>;
      return (data['payments'] as List).cast<Map<String, dynamic>>();
    } catch (e) {
      throw Exception(apiErrorMessage(e, fallback: 'Could not load your payment history.'));
    }
  }

  /// UX-only read for the date step — the real double-booking guard is the
  /// create_multi_day_time_based_booking() RPC at submission time.
  static Future<AvailabilityCheckResult> checkAvailability(
    String productId,
    DateTime start,
    DateTime end,
  ) async {
    String fmt(DateTime d) => d.toIso8601String().substring(0, 10);
    try {
      final response = await _dio.get(
        '/api/mobile/catalog/$productId/availability-check',
        queryParameters: {'start': fmt(start), 'end': fmt(end)},
      );
      final data = response.data as Map<String, dynamic>;
      return AvailabilityCheckResult(
        totalUnits: (data['totalUnits'] as num?)?.toInt() ?? 0,
        availableUnits: (data['availableUnits'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      throw Exception(apiErrorMessage(e, fallback: 'Could not check availability. Please try again.'));
    }
  }

  /// Server builds the productSnapshot/customerSnapshot itself from
  /// authoritative data (never trusts client-sent pricing) — see
  /// app/api/mobile/bookings/route.ts. This only sends what the customer
  /// actually chose: dates, quantity, fulfillment details, notes.
  static Future<Booking> createBooking({
    required String productId,
    required DateTime rentalStartDate,
    required DateTime rentalEndDate,
    required String fulfillmentMethod, // "pickup" | "delivery"
    String? location,
    String? cityMunicipality,
    String? province,
    String? customerNotes,
    int quantity = 1,
  }) async {
    final rentalDays = rentalEndDate.difference(rentalStartDate).inDays.clamp(1, 1000000);
    try {
      final response = await _dio.post('/api/mobile/bookings', data: {
        'productId': productId,
        'quantity': quantity,
        'pickupAt': rentalStartDate.toIso8601String(),
        'rentalDays': rentalDays,
        'fulfillmentMethod': fulfillmentMethod,
        if (location != null) 'location': location,
        if (cityMunicipality != null) 'cityMunicipality': cityMunicipality,
        if (province != null) 'province': province,
        if (customerNotes != null) 'customerNotes': customerNotes,
      });
      final data = response.data as Map<String, dynamic>;
      return Booking.fromJson(data['booking'] as Map<String, dynamic>);
    } catch (e) {
      throw Exception(apiErrorMessage(e, fallback: 'Could not submit your booking. Please try again.'));
    }
  }

  /// Polling-based stand-in for Supabase Realtime, which isn't available
  /// now that the app doesn't hold a direct DB connection. Polls every 5s;
  /// cancel by closing the StreamSubscription (e.g. in State.dispose()).
  static Stream<Map<String, dynamic>?> watchBookingStatus(String bookingId) {
    late final StreamController<Map<String, dynamic>?> controller;
    Timer? timer;

    Future<void> poll() async {
      try {
        final booking = await getBookingById(bookingId);
        if (booking != null) {
          controller.add({'status': bookingStatusToApiValue(booking.status)});
        }
      } catch (_) {
        // Swallow transient poll errors — keep the stream alive.
      }
    }

    controller = StreamController<Map<String, dynamic>?>(
      onListen: () {
        poll();
        timer = Timer.periodic(const Duration(seconds: 5), (_) => poll());
      },
      onCancel: () => timer?.cancel(),
    );
    return controller.stream;
  }
}
