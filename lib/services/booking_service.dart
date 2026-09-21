// lib/services/booking_service.dart
//
// Calls the backend's /api/mobile/bookings* and /api/mobile/catalog/:id/
// availability-check routes. Everything returns typed models (Booking),
// not raw maps — the backend does the Supabase work and hands back clean
// JSON matching src/types/booking.ts.

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:dio/dio.dart';
import '../models/booking.dart';
import '../models/booking_detail.dart';
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
      final response = await _dio.get('/mobile/account/bookings');
      final data = response.data as Map<String, dynamic>;
      final rows = (data['bookings'] as List).cast<Map<String, dynamic>>();
      // Parse row by row: one unreadable booking should not hide all the others.
      final bookings = <Booking>[];
      for (final row in rows) {
        try {
          bookings.add(Booking.fromJson(row));
        } catch (e) {
          debugPrint('Skipping unreadable booking ${row['id']}: $e');
        }
      }
      return bookings;
    } catch (e) {
      throw Exception(apiErrorMessage(e, fallback: 'Could not load your bookings.'));
    }
  }

  static Future<Booking?> getBookingById(String id) async {
    try {
      final response = await _dio.get('/mobile/account/bookings/$id');
      final data = response.data as Map<String, dynamic>;
      return Booking.fromJson(data['booking'] as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw Exception(apiErrorMessage(e, fallback: 'Could not load this booking.'));
    }
  }

  /// Full tracker payload — base booking plus agreement, documents,
  /// statusHistory, payments, receipts, review, emergencyContact, and any
  /// cancellationRequest. Use this for the Booking Detail / Guest Tracker
  /// screen; use getBookingById above for anywhere that only needs the
  /// base Booking (e.g. the bookings list).
  static Future<BookingDetail?> getBookingDetail(String id) async {
    try {
      final response = await _dio.get('/mobile/account/bookings/$id');
      final data = response.data as Map<String, dynamic>;
      return BookingDetail.fromJson(data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw Exception(apiErrorMessage(e, fallback: 'Could not load this booking.'));
    }
  }

  /// NOTE: `reason` must be one of the real app's CANCELLATION_REASON_OPTIONS
  /// (src/types/booking.ts) — not yet confirmed against source at the time
  /// this was written. The backend RPC validates it server-side and returns
  /// a clear error if it doesn't match, so an unconfirmed value fails safe
  /// (user sees "Choose one of the available cancellation reasons.") rather
  /// than corrupting data — but the reason picker UI should use the real
  /// list once available, not free text.
  static Future<BookingDetail> cancelBooking(
    String id, {
    required String reason,
    String? additionalDetails,
  }) async {
    try {
      final response = await _dio.post(
        '/mobile/account/bookings/$id/cancel',
        data: {
          'reason': reason,
          if (additionalDetails != null && additionalDetails.trim().isNotEmpty)
            'additionalDetails': additionalDetails.trim(),
        },
      );
      final data = response.data as Map<String, dynamic>;
      return BookingDetail.fromJson(data);
    } catch (e) {
      throw Exception(apiErrorMessage(e, fallback: 'Could not cancel this booking.'));
    }
  }

  /// "Edit safe details" — only while status is pending and nothing is
  /// locked yet (see BookingDetail.hasLockedProgress /
  /// canCustomerEditBooking in utils/booking_management.dart).
  static Future<BookingDetail> updateBookingDetails(
    String id, {
    required String fulfillmentMethod, // "pickup" | "delivery"
    String? location,
    String? cityMunicipality,
    String? province,
    String? customerNotes,
  }) async {
    try {
      final response = await _dio.post(
        '/mobile/account/bookings/$id/details',
        data: {
          'fulfillmentMethod': fulfillmentMethod,
          if (location != null) 'location': location,
          if (cityMunicipality != null) 'cityMunicipality': cityMunicipality,
          if (province != null) 'province': province,
          if (customerNotes != null) 'customerNotes': customerNotes,
        },
      );
      final data = response.data as Map<String, dynamic>;
      return BookingDetail.fromJson(data);
    } catch (e) {
      throw Exception(apiErrorMessage(e, fallback: 'Could not update this booking.'));
    }
  }

  static Future<List<Map<String, dynamic>>> getMyPayments() async {
    try {
      final response = await _dio.get('/mobile/account/payments');
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
    DateTime end, {
    int quantity = 1,
  }) async {
    String fmt(DateTime d) => d.toIso8601String().substring(0, 10);
    try {
      final response = await _dio.get(
        '/mobile/catalog/$productId/availability-check',
        // The Laravel route reads start_date/end_date (or startDate/endDate).
        // It does NOT read start/end — those were silently ignored, so the
        // check used to cover today only instead of the chosen range.
        queryParameters: {'start_date': fmt(start), 'end_date': fmt(end), 'quantity': quantity},
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

  /// The customer picks a Philippine wall-clock pickup time. A local DateTime's
  /// toIso8601String() carries NO offset, so Supabase would read "3:00 PM" as
  /// 3:00 PM UTC (= 11:00 PM in Manila) and shift fees and dates. Send the same
  /// wall-clock time with an explicit +08:00 offset instead.
  static String _manilaIso(DateTime wallClock) {
    String two(int n) => n.toString().padLeft(2, '0');
    final y = wallClock.year.toString().padLeft(4, '0');
    return '$y-${two(wallClock.month)}-${two(wallClock.day)}'
        'T${two(wallClock.hour)}:${two(wallClock.minute)}:00+08:00';
  }

  /// Sends fresh customer-typed details with every booking — confirmed
  /// against src/services/bookingSubmissionService.ts, which validates and
  /// sends these exact fields rather than reusing the stored profile.
  /// The server still builds productSnapshot itself and never trusts
  /// client-sent pricing.
  static Future<Booking> createBooking({
    required String productId,
    required DateTime rentalStartDate,
    required int rentalDays,
    required String fulfillmentMethod, // "pickup" | "delivery"
    required String customerFullName,
    required String customerEmail,
    required String customerPhone,
    required String customerStreetBarangay,
    required String customerCityMunicipality,
    required String customerProvince,
    required String customerFacebookLink,
    required String customerInstagramLink,
    String? location,
    String? cityMunicipality,
    String? province,
    String? customerNotes,
    int quantity = 1,
  }) async {
    try {
      final response = await _dio.post('/mobile/bookings', data: {
        'productId': productId,
        'quantity': quantity,
        'pickupAt': _manilaIso(rentalStartDate),
        'rentalDays': rentalDays,
        'fulfillmentMethod': fulfillmentMethod,
        'customerFullName': customerFullName,
        'customerEmail': customerEmail,
        'customerPhone': customerPhone,
        'customerStreetBarangay': customerStreetBarangay,
        'customerCityMunicipality': customerCityMunicipality,
        'customerProvince': customerProvince,
        'customerFacebookLink': customerFacebookLink,
        'customerInstagramLink': customerInstagramLink,
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