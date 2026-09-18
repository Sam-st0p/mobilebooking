import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ApiConfig {
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000/api',
  );

  static bool get isConfigured => !baseUrl.contains('YOUR-BACKEND-DOMAIN') && baseUrl.isNotEmpty;
}

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
          String? token = await _storage.read(key: _accessTokenKey);
          if (token == null) {
            try {
              token = Supabase.instance.client.auth.currentSession?.accessToken;
            } catch (_) {}
          }

          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401 && error.requestOptions.extra['retried'] != true) {
            final refreshed = await _tryRefresh();
            if (refreshed) {
              final retryOptions = error.requestOptions;
              retryOptions.extra['retried'] = true;
              final token = await _storage.read(key: _accessTokenKey);
              retryOptions.headers['Authorization'] = 'Bearer $token';
              try {
                final retryResponse = await _dio.fetch(retryOptions);
                return handler.resolve(retryResponse);
              } catch (_) {}
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
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
  }

  Future<bool> hasSession() async {
    final token = await _storage.read(key: _accessTokenKey);
    if (token != null) return true;
    try {
      return Supabase.instance.client.auth.currentSession != null;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _tryRefresh() async {
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    if (refreshToken != null) {
      try {
        final response = await Dio(BaseOptions(baseUrl: ApiConfig.baseUrl)).post(
          '/mobile/auth/refresh',
          data: {'refreshToken': refreshToken},
        );
        final data = response.data as Map<String, dynamic>;
        if (data['accessToken'] != null && data['refreshToken'] != null) {
          await saveSession(
            accessToken: data['accessToken'] as String,
            refreshToken: data['refreshToken'] as String,
          );
          return true;
        }
      } catch (_) {}
    }

    try {
      final result = await Supabase.instance.client.auth.refreshSession();
      return result.session != null;
    } catch (_) {
      await clearSession();
      return false;
    }
  }
}

String apiErrorMessage(Object error, {String fallback = 'Something went wrong. Please try again.'}) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['error'] is String) return data['error'] as String;
  }
  return fallback;
}
