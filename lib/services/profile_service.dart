// lib/services/profile_service.dart 

import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile.dart';
import 'supabase_client.dart';

/// Port of the customer-relevant parts of `src/services/userService.ts`.
/// (Admin-only helpers like listing every profile are intentionally left
/// out — this is the customer app.)
class ProfileService {
  static Future<UserProfile?> getUserProfile(String uid) async {
    if (uid.isEmpty) return null;
    final data =
        await supabase.from('profiles').select('*').eq('id', uid).maybeSingle();
    if (data == null) return null;
    return UserProfile.fromRow(data);
  }

  static Future<void> updateUserProfile(
    String uid, {
    String? displayName,
    String? phoneNumber,
    String? fullAddress,
    String? facebookLink,
    String? instagramLink,
  }) async {
    final updates = <String, dynamic>{};
    if (displayName != null) updates['display_name'] = displayName;
    if (phoneNumber != null) updates['phone_number'] = phoneNumber;
    if (fullAddress != null) updates['full_address'] = fullAddress;
    if (facebookLink != null) updates['facebook_url'] = facebookLink;
    if (instagramLink != null) updates['instagram_url'] = instagramLink;
    if (updates.isEmpty) return;

    await supabase.from('profiles').update(updates).eq('id', uid);
  }

  /// ASSUMPTION: bucket name 'avatars' — not confirmed against the real
  /// website schema (same caveat as booking-documents earlier). If the
  /// website uses a different bucket for profile photos, this is the only
  /// string that needs to change.
  static const _avatarBucket = 'avatars';

  static Future<void> uploadProfilePhoto(String uid, Uint8List bytes, String extension) async {
    final path = '$uid/avatar.$extension';
    await supabase.storage.from(_avatarBucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    await supabase.from('profiles').update({'photo_path': path}).eq('id', uid);
  }

  static String? photoUrl(String? photoPath) {
    if (photoPath == null || photoPath.isEmpty) return null;
    return supabase.storage.from(_avatarBucket).getPublicUrl(photoPath);
  }
}