// lib/services/auth_provider.dart
import 'package:flutter/foundation.dart';
import '../models/user_profile.dart';
import 'auth_service.dart';
import 'profile_service.dart';

/// App-wide auth/session state. There's no more Supabase auth-state stream
/// to listen to — the backend issues a plain JWT, so this provider checks
/// for a stored token on startup and refreshes explicitly after
/// sign-in/sign-out, rather than reacting to a live stream.
class AppAuth extends ChangeNotifier {
  AuthUser? user;
  UserProfile? profile;
  bool loading = true;

  Future<void> init() async {
    loading = true;
    notifyListeners();

    final hasSession = await AuthService.hasSession();
    if (hasSession) {
      await _loadProfile();
    } else {
      user = null;
      profile = null;
    }

    loading = false;
    notifyListeners();
  }

  Future<void> _loadProfile() async {
    try {
      final fetchedProfile = await ProfileService.getMyProfile();
      if (fetchedProfile == null) {
        // Token was present but rejected/expired and couldn't be refreshed.
        user = null;
        profile = null;
        return;
      }
      profile = fetchedProfile;
      user = AuthUser(id: fetchedProfile.id, email: fetchedProfile.email);
    } catch (_) {
      user = null;
      profile = null;
    }
  }

  /// Call after AuthService.verifyEmailOtp() succeeds.
  Future<void> onSignedIn(AuthUser signedInUser) async {
    user = signedInUser;
    loading = true;
    notifyListeners();
    await _loadProfile();
    loading = false;
    notifyListeners();
  }

  Future<void> refreshProfile() async {
    await _loadProfile();
    notifyListeners();
  }

  Future<void> signOut() async {
    await AuthService.logout();
    user = null;
    profile = null;
    notifyListeners();
  }
}
