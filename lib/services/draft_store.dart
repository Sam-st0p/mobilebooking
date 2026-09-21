// lib/services/draft_store.dart
//
// Tiny wrapper over SharedPreferences for the "Progress saved on this
// device" feature. Values are plain JSON. Files and signature images are
// never passed in here — callers only store text/choices.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class DraftSnapshot {
  final Map<String, dynamic> values;
  final DateTime savedAt;
  const DraftSnapshot({required this.values, required this.savedAt});
}

class DraftStore {
  DraftStore._();

  static Future<DraftSnapshot?> load(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final values = decoded['values'];
      if (values is! Map<String, dynamic>) return null;
      final savedAt = DateTime.tryParse((decoded['savedAt'] as String?) ?? '') ?? DateTime.now();
      return DraftSnapshot(values: values, savedAt: savedAt);
    } catch (_) {
      return null; // A corrupt draft is not worth surfacing.
    }
  }

  /// Returns the save time, or null if saving failed.
  static Future<DateTime?> save(String key, Map<String, dynamic> values) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      await prefs.setString(key, jsonEncode({'values': values, 'savedAt': now.toIso8601String()}));
      return now;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {}
  }
}