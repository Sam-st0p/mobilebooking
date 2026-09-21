// lib/services/availability_service.dart

import 'package:dio/dio.dart';
import 'api_client.dart';

/// One day from GET /mobile/catalog/:id/availability-calendar.
class DayAvailability {
  final int totalUnits;
  final int availableUnits;

  /// Units that are unavailable because of CONFIRMED bookings (as opposed to
  /// bookings still pending review).
  final int confirmedUnavailableUnits;

  const DayAvailability({
    required this.totalUnits,
    required this.availableUnits,
    required this.confirmedUnavailableUnits,
  });

  bool get isBooked => availableUnits <= 0;

  /// Fully booked and every unit is held by a confirmed booking.
  bool get isBookedConfirmed => isBooked && totalUnits > 0 && confirmedUnavailableUnits >= totalUnits;
}

/// Calls GET /api/mobile/catalog/:id/availability — a UX-only read for the
/// reservation flow's date picker (fully-booked days get disabled). The
/// real double-booking guard is still the backend's create_booking() RPC
/// at submission time, not this endpoint.
class AvailabilityService {
  static const maxRentalDays = 30;
  static const _calendarWindowDays = 180;

  static Dio get _dio => ApiClient.instance.dio;

  static String toDateKey(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return d.toIso8601String().substring(0, 10);
  }

  /// Date keys ("YYYY-MM-DD"), within the next 180 days, on which every
  /// active unit of a product is already held.
  static Future<Set<String>> getFullyBookedDateKeys(String productId) async {
    final today = DateTime.now();
    final windowEnd = today.add(const Duration(days: _calendarWindowDays));

    try {
      final response = await _dio.get(
        '/api/mobile/catalog/$productId/availability',
        queryParameters: {
          'start': toDateKey(today),
          'end': toDateKey(windowEnd),
        },
      );
      final data = response.data as Map<String, dynamic>;
      return Set<String>.from(data['fullyBookedDates'] as List);
    } catch (e) {
      throw Exception(apiErrorMessage(e, fallback: 'Could not load availability for this product.'));
    }
  }

  /// Per-day availability for the reservation calendar, keyed "YYYY-MM-DD".
  /// Backed by the Laravel route /catalog/{id}/availability-calendar, which
  /// wraps get_product_availability_calendar(). Throws on failure — callers
  /// should treat the calendar as optional decoration.
  static Future<Map<String, DayAvailability>> getCalendar(
    String productId,
    DateTime start,
    DateTime end,
  ) async {
    try {
      final response = await _dio.get(
        '/mobile/catalog/$productId/availability-calendar',
        queryParameters: {'start_date': toDateKey(start), 'end_date': toDateKey(end)},
      );
      final data = response.data as Map<String, dynamic>;
      final days = (data['days'] as List?) ?? const [];
      final result = <String, DayAvailability>{};
      for (final raw in days) {
        final row = raw as Map<String, dynamic>;
        final date = (row['date'] as String?) ?? '';
        if (date.length < 10) continue;
        result[date.substring(0, 10)] = DayAvailability(
          totalUnits: (row['totalUnits'] as num?)?.toInt() ?? 0,
          availableUnits: (row['availableUnits'] as num?)?.toInt() ?? 0,
          confirmedUnavailableUnits: (row['confirmedUnavailableUnits'] as num?)?.toInt() ?? 0,
        );
      }
      return result;
    } catch (e) {
      throw Exception(apiErrorMessage(e, fallback: 'Could not load the availability calendar.'));
    }
  }

  static Future<bool> isRangeAvailable(
    String productId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final fullyBooked = await getFullyBookedDateKeys(productId);
    for (var d = startDate; !d.isAfter(endDate); d = d.add(const Duration(days: 1))) {
      if (fullyBooked.contains(toDateKey(d))) return false;
    }
    return true;
  }
}