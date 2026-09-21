import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import '../models/user_profile.dart';
import 'api_client.dart';

/// Calls /api/mobile/account/profile* routes.
class ProfileService {
  static Dio get _dio => ApiClient.instance.dio;

  static Future<UserProfile?> getMyProfile() async {
    try {
      final response = await _dio.get('/mobile/account/profile');
      final data = response.data as Map<String, dynamic>;
      return UserProfile.fromJson(data['profile'] as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 404) return null;
      throw Exception(apiErrorMessage(e, fallback: 'Could not load your profile.'));
    }
  }

  /// `uid` isn't actually used (the backend identifies the caller from the
  /// bearer token), but kept as a parameter for call-site compatibility.
  static Future<UserProfile> updateUserProfile(
    String uid, {
    String? displayName,
    String? phoneNumber,
    String? fullAddress,
    String? facebookLink,
    String? instagramLink,
  }) async {
    try {
      final response = await _dio.put('/mobile/account/profile', data: {
        if (displayName != null) 'displayName': displayName,
        if (phoneNumber != null) 'phoneNumber': phoneNumber,
        if (fullAddress != null) 'fullAddress': fullAddress,
        if (facebookLink != null) 'facebookLink': facebookLink,
        if (instagramLink != null) 'instagramLink': instagramLink,
      });
      final data = response.data as Map<String, dynamic>;
      return UserProfile.fromJson(data['profile'] as Map<String, dynamic>);
    } catch (e) {
      throw Exception(apiErrorMessage(e, fallback: 'Could not update your profile.'));
    }
  }

  /// `uid` isn't actually used (same as updateUserProfile) — kept for
  /// call-site compatibility with the screen.
  static Future<String> uploadProfilePhoto(String uid, Uint8List bytes, String extension) async {
    try {
      final mimeType = switch (extension.toLowerCase()) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: 'photo.$extension', contentType: MediaType.parse(mimeType)),
      });
      final response = await _dio.post('/mobile/account/profile/photo', data: formData);
      final data = response.data as Map<String, dynamic>;
      return data['photoUrl'] as String;
    } catch (e) {
      throw Exception(apiErrorMessage(e, fallback: 'Could not upload your photo.'));
    }
  }

  /// The backend now resolves photoPath to a full public URL itself (see
  /// UserProfile.photoUrl) — this just returns that, kept as a static
  /// helper for call-site compatibility with screens that still call
  /// `ProfileService.photoUrl(profile.photoPath)` expecting a sync string.
  /// Prefer `profile.photoUrl` directly in new code.
  static String? photoUrl(String? photoPathOrUrl) {
    if (photoPathOrUrl == null || photoPathOrUrl.isEmpty) return null;
    return photoPathOrUrl;
  }
}