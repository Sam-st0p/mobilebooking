// lib/services/favorites_service.dart

import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

/// Port of `hooks/useFavorites.ts`. Uses SharedPreferences as the mobile
/// equivalent of the web app's localStorage — same key, same "list of
/// product ids" shape, just persisted natively instead of in the browser.
class FavoritesService {
  static const _storageKey = 'maddy-cassy-favorites';
  static final _controller = StreamController<List<String>>.broadcast();
  static List<String> _cache = [];

  static Stream<List<String>> get favoritesStream => _controller.stream;
  static List<String> get current => _cache;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _cache = prefs.getStringList(_storageKey) ?? [];
    _controller.add(_cache);
  }

  static Future<void> toggleFavorite(String productId) async {
    final prefs = await SharedPreferences.getInstance();
    final next = List<String>.from(_cache);
    if (next.contains(productId)) {
      next.remove(productId);
    } else {
      next.add(productId);
    }
    await prefs.setStringList(_storageKey, next);
    _cache = next;
    _controller.add(_cache);
  }

  static bool isFavorite(String productId) => _cache.contains(productId);
}