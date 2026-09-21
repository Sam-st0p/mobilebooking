// lib/services/documents_service.dart
//
// Calls the real, confirmed two-endpoint flow (Step 4 + the customer side
// of Step 5, combined into one submission) — mirrors
// BookingDocumentController::uploadDocument()/submitDocuments(), which
// itself mirrors app/api/bookings/[bookingId]/documents/upload and
// .../submit on the real Next.js app.
//
// NOT implemented: reusing previously-approved documents
// (reusedDocuments). That requires an endpoint to list the customer's
// existing approved customer_documents rows, which hasn't been confirmed
// against real source — every submission through this service uploads
// fresh files. Safe (the backend always accepts fresh uploads), just not
// the full feature set.

import 'dart:math';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'api_client.dart';

/// kind must be one of: idOne, idTwo, selfie, emergencyId, signature —
/// matches BookingDocumentController::UPLOAD_KINDS exactly.
class DocumentUpload {
  final Uint8List bytes;
  final String filename;
  final String mimeType;
  const DocumentUpload({required this.bytes, required this.filename, required this.mimeType});
}

class DocumentsService {
  static Dio get _dio => ApiClient.instance.dio;

  /// A random v4-shaped UUID for grouping one submission's uploads —
  /// server only checks the shape (36 hex/dash chars), not real RFC 4122
  /// randomness quality, so a simple Random generator is fine here.
  static String generateSubmissionId() {
    final rand = Random.secure();
    String hex(int n) => List.generate(n, (_) => rand.nextInt(16).toRadixString(16)).join();
    return '${hex(8)}-${hex(4)}-4${hex(3)}-${(8 + rand.nextInt(4)).toRadixString(16)}${hex(3)}-${hex(12)}';
  }

  /// POST /mobile/bookings/{bookingId}/documents/upload?kind=...&submissionId=...
  /// Returns the storage path to pass into submitDocuments's `files` map.
  static Future<String> uploadDocument({
    required String bookingId,
    required String kind, // idOne | idTwo | selfie | emergencyId | signature
    required String submissionId,
    required DocumentUpload file,
  }) async {
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          file.bytes,
          filename: file.filename,
          contentType: MediaType.parse(file.mimeType),
        ),
      });
      final response = await _dio.post(
        '/mobile/bookings/$bookingId/documents/upload',
        data: formData,
        queryParameters: {'kind': kind, 'submissionId': submissionId},
      );
      final data = response.data as Map<String, dynamic>;
      if (data['success'] != true || data['path'] is! String) {
        throw Exception(data['error']?.toString() ?? 'This file could not be uploaded.');
      }
      return data['path'] as String;
    } catch (e) {
      throw Exception(apiErrorMessage(e, fallback: 'This file could not be uploaded.'));
    }
  }

  /// POST /mobile/bookings/{bookingId}/documents/submit
  /// [files] must include emergencyId and signature (always required) plus
  /// whichever of idOne/idTwo/selfie were freshly uploaded (paths, not
  /// reused — see the NOT-implemented note above).
  static Future<void> submitDocuments({
    required String bookingId,
    required String submissionId,
    required Map<String, String> files,
    required String facebookLink,
    required String instagramLink,
    required String emergencyFullName,
    required String emergencyRelationship,
    required String emergencyPhone,
    required String emergencyFacebookLink,
    required Map<String, bool> acknowledgements,
    required String signatureMethod, // "drawn" | "uploaded"
    required String typedFullName,
  }) async {
    try {
      final response = await _dio.post('/mobile/bookings/$bookingId/documents/submit', data: {
        'submissionId': submissionId,
        'files': files,
        'reusedDocuments': const <String, String>{},
        'facebookLink': facebookLink,
        'instagramLink': instagramLink,
        'emergencyContact': {
          'fullName': emergencyFullName,
          'relationship': emergencyRelationship,
          'phone': emergencyPhone,
          'facebookLink': emergencyFacebookLink,
        },
        'acknowledgements': acknowledgements,
        'signatureMethod': signatureMethod,
        'typedFullName': typedFullName,
      });
      final data = response.data as Map<String, dynamic>;
      if (data['success'] != true) {
        throw Exception(data['error']?.toString() ?? 'The documents could not be submitted.');
      }
    } catch (e) {
      throw Exception(apiErrorMessage(e, fallback: 'The documents could not be submitted. Please try again.'));
    }
  }
}