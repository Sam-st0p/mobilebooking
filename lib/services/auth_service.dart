import 'package:dio/dio.dart';
import 'api_client.dart';

class AuthUser {
  final String id;
  final String? email;
  const AuthUser({required this.id, this.email});

  factory AuthUser.fromJson(Map<String, dynamic> json) =>
      AuthUser(id: json['id'] as String, email: json['email'] as String?);
}

class SignUpProfile {
  final String displayName;
  final String phoneNumber;
  final String birthDate;

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

class AuthService {
  static Dio get _dio => ApiClient.instance.dio;

  static Future<void> sendSignInOtp(String email) async {
    try {
      await _dio.post('/mobile/auth/request-otp', data: {
        'email': email,
        'mode': 'sign-in',
      });
    } catch (e) {
      if (e is DioException) {
        throw Exception('API Error (${e.response?.statusCode}): ${e.message}');
      }
      throw Exception(e.toString());
    }
  }

  static Future<void> sendSignUpOtp(String email, SignUpProfile profile) async {
    try {
      await _dio.post('/mobile/auth/request-otp', data: {
        'email': email,
        'mode': 'sign-up',
        'profile': profile.toJson(),
      });
    } catch (e) {
      if (e is DioException) {
        throw Exception('API Error (${e.response?.statusCode}): ${e.message}');
      }
      throw Exception(e.toString());
    }
  }

  static Future<AuthUser> verifyEmailOtp(String email, String code) async {
    try {
      final response = await _dio.post('/mobile/auth/verify-otp', data: {
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
      if (e is DioException) {
        throw Exception('API Error (${e.response?.statusCode}): ${e.message}');
      }
      throw Exception(e.toString());
    }
  }

  static Future<void> logout() async {
    await ApiClient.instance.clearSession();
  }

  static Future<bool> hasSession() => ApiClient.instance.hasSession();
}
