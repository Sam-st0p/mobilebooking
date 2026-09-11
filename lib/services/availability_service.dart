// lib/services/availability_service.dart

import 'package:dio/dio.dart';
import 'api_client.dart';

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
