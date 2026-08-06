// lib/services/auth_provider.dart

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile.dart';
import 'auth_service.dart';
import 'profile_service.dart';

/// Port of `src/contexts/AuthContext.tsx`, scoped to the customer app (no
/// `isAdmin` branch — this app never shows the admin dashboard). Wrap the
/// app in a `ChangeNotifierProvider(create: (_) => AppAuth()..init())`.
class AppAuth extends ChangeNotifier {
  User? user;
  UserProfile? profile;
  bool loading = true;

  void init() {
    AuthService.authStateChanges.listen(_onUserChanged);
    _onUserChanged(AuthService.currentUser);
  }

  Future<void> _onUserChanged(User? nextUser) async {
    user = nextUser;
    loading = true;
    notifyListeners();

    try {
      if (nextUser != null) {
        profile = await ProfileService.getUserProfile(nextUser.id);
      } else {
        profile = null;
      }
    } catch (_) {
      profile = null;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refreshProfile() async {
    final currentUser = user;
    if (currentUser != null) {
      profile = await ProfileService.getUserProfile(currentUser.id);
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await AuthService.logout();
  }
}
