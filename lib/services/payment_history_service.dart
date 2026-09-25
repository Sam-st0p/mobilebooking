// lib/services/payment_history_service.dart

import 'package:dio/dio.dart';
import '../models/payment_record.dart';
import 'api_client.dart';

class PaymentHistoryService {
  PaymentHistoryService._();

  static Dio get _dio => ApiClient.instance.dio;

  /// GET /account/payments — every GCash payment the signed-in customer has
  /// submitted, newest first. Was previously "Coming soon" — no backend
  /// route existed for this at all.
  static Future<List<PaymentRecord>> getMyPayments() async {
    try {
      final response = await _dio.get('/mobile/account/payments');
      final data = response.data as Map<String, dynamic>;
      final rows = (data['payments'] as List).cast<Map<String, dynamic>>();
      return rows.map(PaymentRecord.fromJson).toList();
    } catch (e) {
      throw Exception(apiErrorMessage(e, fallback: 'Could not load your payment history.'));
    }
  }
}