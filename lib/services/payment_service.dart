// lib/services/payment_service.dart
//
// Calls POST /api/mobile/payment-submissions — confirmed against
// PaymentSubmissionController::store(). Note this endpoint uses snake_case
// field names (booking_id, declared_amount, etc.), unlike the camelCase
// used by /mobile/bookings — that's the real backend's own inconsistency,
// not a mistake here.
//
// GAP: the real StepPaymentSubmission.tsx form also requires "name of
// account used" and "11-digit GCash mobile number used" (pay-account-name,
// pay-account-number), but PaymentSubmissionController's validator has no
// matching fields — only booking_id/stage/declared_amount/payment_method/
// external_reference/proof are read. These two values are still collected
// and sent below (Laravel will just ignore them for now, harmlessly, since
// Validator::validated() drops anything not in the rules) so nothing needs
// to change here once the real column/field is confirmed and added
// server-side — only PaymentSubmissionController.php would need updating.

import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'api_client.dart';

class PaymentSubmissionResult {
  final String submissionId;
  const PaymentSubmissionResult({required this.submissionId});
}

class PaymentService {
  static Dio get _dio => ApiClient.instance.dio;

  /// [stage] is "down_payment" for this initial guided-reservation payment
  /// — confirmed as one of the three real values (down_payment|balance|
  /// other) in PaymentSubmissionController, "down_payment" being the only
  /// one that fits a brand-new booking's first payment regardless of
  /// whether the customer chose the 50% or full-payment option (that
  /// choice affects declaredAmount, not stage).
  static Future<PaymentSubmissionResult> submitPayment({
    required String bookingId,
    required double declaredAmount,
    required String referenceNumber,
    required String accountName,
    required String accountNumber,
    required Uint8List proofBytes,
    required String proofFilename,
    required String proofMimeType,
    String stage = 'down_payment',
  }) async {
    try {
      final formData = FormData.fromMap({
        'booking_id': bookingId,
        'stage': stage,
        'declared_amount': declaredAmount,
        'payment_method': 'gcash',
        'external_reference': referenceNumber,
        // Not yet read server-side — see the GAP note above.
        'account_name': accountName,
        'account_number': accountNumber,
        'proof': MultipartFile.fromBytes(
          proofBytes,
          filename: proofFilename,
          contentType: MediaType.parse(proofMimeType),
        ),
      });
      final response = await _dio.post('/mobile/payment-submissions', data: formData);
      final data = response.data as Map<String, dynamic>;
      final submission = (data['data'] as Map<String, dynamic>?)?['submission'] as Map<String, dynamic>?;
      return PaymentSubmissionResult(submissionId: submission?['id']?.toString() ?? '');
    } catch (e) {
      throw Exception(apiErrorMessage(e, fallback: 'Could not submit your payment. Please try again.'));
    }
  }
}