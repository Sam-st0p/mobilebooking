// lib/services/auth_service.dart

import 'package:dio/dio.dart';
import 'api_client.dart';

/// Lightweight stand-in for the old supabase_flutter `User` — the app now
/// only knows what the backend's verify-otp response tells it.
class AuthUser {
  final String id;
  final String? email;
  const AuthUser({required this.id, this.email});

  factory AuthUser.fromJson(Map<String, dynamic> json) =>
      AuthUser(id: json['id'] as String, email: json['email'] as String?);
}

/// Profile fields collected upfront on sign-up (matches the web app's
/// expanded sign-up form) — passed through to Supabase as user metadata so
/// the profile row is populated immediately on first verified code.
class SignUpProfile {
  final String displayName;
  final String phoneNumber; // exactly 11 digits, PH format
  final String birthDate; // YYYY-MM-DD

  const SignUpProfile({
    required this.displayName,
    required this.phoneNumber,
    required this.birthDate,
  });

  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'phoneNumber': phoneNumber,
        'birthDate': birthDate,
      };
}

/// Calls the backend's /api/mobile/auth/* routes instead of talking to
/// Supabase Auth directly. Customer accounts are email-OTP only — no
/// password — matching the web app ("No password is needed for customer
/// accounts").
class AuthService {
  static Dio get _dio => ApiClient.instance.dio;

  static Future<void> sendSignInOtp(String email) async {
    try {
      await _dio.post('/api/mobile/auth/request-otp', data: {
        'email': email,
        'mode': 'sign-in',
      });
    } catch (e) {
      throw Exception(apiErrorMessage(e, fallback: "Couldn't send a code to that email."));
    }
  }

  static Future<void> sendSignUpOtp(String email, SignUpProfile profile) async {
    try {
      await _dio.post('/api/mobile/auth/request-otp', data: {
        'email': email,
        'mode': 'sign-up',
        'profile': profile.toJson(),
      });
    } catch (e) {
      throw Exception(apiErrorMessage(e, fallback: "Couldn't send a code to that email."));
    }
  }

  static Future<AuthUser> verifyEmailOtp(String email, String code) async {
    try {
      final response = await _dio.post('/api/mobile/auth/verify-otp', data: {
        'email': email,
        'code': code,
      });
      final data = response.data as Map<String, dynamic>;
      await ApiClient.instance.saveSession(
        accessToken: data['accessToken'] as String,
        refreshToken: data['refreshToken'] as String,
      );
      return AuthUser.fromJson(data['user'] as Map<String, dynamic>);
    } catch (e) {
      throw Exception(apiErrorMessage(e, fallback: 'That code is invalid or has expired.'));
    }
  }

  static Future<void> logout() async {
    await ApiClient.instance.clearSession();
  }

  static Future<bool> hasSession() => ApiClient.instance.hasSession();
}
