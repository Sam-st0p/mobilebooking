// lib/services/api_client.dart

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Base URL of the Mobile Application Backend / API Gateway (your Next.js
/// app's /api/mobile/* routes). Pass this in the same way as before:
///   flutter run --dart-define-from-file=config.json
/// with { "API_BASE_URL": "https://your-app.example.com" } in config.json.
class ApiConfig {
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://YOUR-BACKEND-DOMAIN.example.com',
  );

  static bool get isConfigured => !baseUrl.contains('YOUR-BACKEND-DOMAIN');
}

/// Thin wrapper around Dio that is the app's single door to the backend.
/// Every other service (auth, catalog, account) goes through this — nothing
/// in the app talks to Supabase directly anymore; the backend does that.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const _storage = FlutterSecureStorage();
  static const _accessTokenKey = 'mc_access_token';
  static const _refreshTokenKey = 'mc_refresh_token';

  late final Dio _dio = Dio(
    BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      contentType: 'application/json',
    ),
  )..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.read(key: _accessTokenKey);
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          // Access token expired — try the refresh token once, then retry
          // the original request. If that also fails, the caller (usually
          // AppAuth) treats it as "signed out".
          if (error.response?.statusCode == 401 && error.requestOptions.extra['retried'] != true) {
            final refreshed = await _tryRefresh();
            if (refreshed) {
              final retryOptions = error.requestOptions;
              retryOptions.extra['retried'] = true;
              final token = await _storage.read(key: _accessTokenKey);
              retryOptions.headers['Authorization'] = 'Bearer $token';
              try {
                final response = await _dio.fetch(retryOptions);
                return handler.resolve(response);
              } catch (_) {
                // fall through to original error
              }
            }
          }
          handler.next(error);
        },
      ),
    );

  Dio get dio => _dio;

  Future<void> saveSession({required String accessToken, required String refreshToken}) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  Future<void> clearSession() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }

  Future<bool> hasSession() async => (await _storage.read(key: _accessTokenKey)) != null;

  Future<bool> _tryRefresh() async {
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    if (refreshToken == null) return false;
    try {
      final response = await Dio(BaseOptions(baseUrl: ApiConfig.baseUrl)).post(
        '/api/mobile/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final data = response.data as Map<String, dynamic>;
      if (data['success'] == true) {
        await saveSession(
          accessToken: data['accessToken'] as String,
          refreshToken: data['refreshToken'] as String,
        );
        return true;
      }
      return false;
    } catch (_) {
      await clearSession();
      return false;
    }
  }
}

/// Consistent error message extraction from the backend's
/// `{ success: false, error: "..." }` shape.
String apiErrorMessage(Object error, {String fallback = 'Something went wrong. Please try again.'}) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['error'] is String) return data['error'] as String;
  }
  return fallback;
}
