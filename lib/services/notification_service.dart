// lib/services/notification_service.dart
//
// Calls the backend's /api/mobile/notifications endpoints. No realtime
// push is wired up yet — the real web app itself falls back to a 30s
// poll + focus refresh alongside its realtime channel (see
// subscribeToUserNotifications in notificationService.ts), so polling
// from Flutter matches that fallback behavior rather than inventing
// something new.

import 'package:dio/dio.dart';
import '../models/app_notification.dart';
import 'api_client.dart';

class NotificationService {
  static Dio get _dio => ApiClient.instance.dio;

  static Future<List<AppNotification>> getNotifications() async {
    try {
      final response = await _dio.get('/mobile/notifications');
      final data = response.data as Map<String, dynamic>;
      final rows = (data['notifications'] as List).cast<Map<String, dynamic>>();
      return rows.map(AppNotification.fromJson).toList();
    } catch (e) {
      throw Exception(apiErrorMessage(e, fallback: 'Could not load notifications.'));
    }
  }

  static Future<AppNotification> markRead(String id) async {
    try {
      final response = await _dio.post('/mobile/notifications/$id/read');
      final data = response.data as Map<String, dynamic>;
      return AppNotification.fromJson(data['notification'] as Map<String, dynamic>);
    } catch (e) {
      throw Exception(apiErrorMessage(e, fallback: 'Could not update this notification.'));
    }
  }
}