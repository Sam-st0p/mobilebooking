import 'dart:convert';

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
      connectTimeout: const Duration(seconds: 20),
      // The backend talks to a distant database (a single query can take ~2.5 s) and
      // uploads run several of them, so 15 s was too tight and reported healthy uploads
      // as failures.
      receiveTimeout: const Duration(seconds: 90),
      sendTimeout: const Duration(seconds: 90),
      contentType: 'application/json',
      // Ask for JSON errors. Without this Laravel answers uncaught exceptions with an
      // HTML page, which the app cannot read — so every crash looked like a generic
      // failure. With it, the exception message comes back as JSON and shows in the app.
      headers: const {'Accept': 'application/json'},
    ),
  )..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          String? token = await _storage.read(key: _accessTokenKey);

          // Refresh BEFORE sending when the access token is expired or about to
          // expire. Supabase access tokens last ~1 hour, and multipart uploads
          // (payment proof, documents) cannot be replayed after a 401, so
          // waiting for the 401 made those requests fail with a session error.
          if (token != null && !options.path.contains('/auth/') && _isExpiredOrExpiring(token)) {
            if (await _refreshOnce()) {
              token = await _storage.read(key: _accessTokenKey);
            }
          }

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
            final refreshed = await _refreshOnce();
            if (refreshed) {
              final retryOptions = error.requestOptions;
              retryOptions.extra['retried'] = true;
              // A FormData body can only be sent once; clone it for the replay.
              final body = retryOptions.data;
              if (body is FormData) retryOptions.data = body.clone();
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

  Future<bool>? _refreshInFlight;

  /// Only ever one refresh at a time: Supabase rotates refresh tokens, so two
  /// parallel refreshes with the same token would make the second one fail.
  Future<bool> _refreshOnce() {
    return _refreshInFlight ??= _tryRefresh().whenComplete(() => _refreshInFlight = null);
  }

  /// True when the JWT's `exp` claim is in the past or within [leeway].
  static bool _isExpiredOrExpiring(String jwt, {Duration leeway = const Duration(seconds: 60)}) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return false;
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final exp = (jsonDecode(payload) as Map<String, dynamic>)['exp'];
      if (exp is! num) return false;
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
      return DateTime.now().isAfter(expiresAt.subtract(leeway));
    } catch (_) {
      return false; // Can't tell — let the server decide.
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
    if (data is Map) {
      final code = data['error'];
      final message = data['message'];
      // Some endpoints (payments) answer {error: "SOME_CODE", message: "Readable text"}.
      // Prefer the readable text when `error` is just a machine code.
      final looksLikeCode = code is String && RegExp(r'^[A-Z0-9_]+$').hasMatch(code);
      if (message is String && message.isNotEmpty && (code is! String || looksLikeCode)) return message;
      if (code is String) return code;
    }
  }
  return fallback;
}