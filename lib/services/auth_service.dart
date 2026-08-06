// lib/services/auth_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_client.dart';

/// Port of `src/services/authService.ts`. Same Supabase Auth calls
/// (email OTP for sign-up/verification, email+password for sign-in).
class AuthService {
  /// Sends a 6-digit one-time code to the given email via Supabase's native
  /// email OTP delivery. Used for both customer sign-in (existing accounts
  /// only, shouldCreateUser: false) and sign-up (creates the account on
  /// first verified code, shouldCreateUser: true).
  static Future<void> sendEmailOtp(
    String email, {
    bool shouldCreateUser = false,
  }) async {
    await supabase.auth.signInWithOtp(
      email: email,
      shouldCreateUser: shouldCreateUser,
    );
  }

  static Future<User> verifyEmailOtp(String email, String token) async {
    final response = await supabase.auth.verifyOTP(
      email: email,
      token: token,
      type: OtpType.email,
    );
    final user = response.user;
    if (user == null) {
      throw Exception('The verification code could not be confirmed.');
    }
    return user;
  }

  static Future<User> loginWithEmail(String email, String password) async {
    final response = await supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
    final user = response.user;
    if (user == null) {
      throw Exception('Could not sign in.');
    }
    return user;
  }

  static Future<void> requestPasswordReset(String email) async {
    await supabase.auth.resetPasswordForEmail(email);
  }

  static Future<void> logout() async {
    await supabase.auth.signOut();
  }

  /// Stream of the current user, mirroring subscribeToAuthChanges().
  static Stream<User?> get authStateChanges =>
      supabase.auth.onAuthStateChange.map((event) => event.session?.user);

  static User? get currentUser => supabase.auth.currentUser;
}
