// lib/models/app_notification.dart
//
// Mirrors NotificationController's response, which mirrors the real
// `notifications` table (confirmed via src/services/notificationService.ts).
// USER-scoped, not booking-scoped.

class AppNotification {
  final String id;
  final String userId;
  final String? bookingId;
  final String type;
  final String title;
  final String message;
  final String? actionUrl;
  final bool isRead;
  final DateTime createdAt;
  final DateTime? readAt;
  final DateTime? expiresAt;

  const AppNotification({
    required this.id,
    required this.userId,
    this.bookingId,
    required this.type,
    required this.title,
    required this.message,
    this.actionUrl,
    required this.isRead,
    required this.createdAt,
    this.readAt,
    this.expiresAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    DateTime? parseOpt(String? key) => json[key] != null ? DateTime.parse(json[key] as String) : null;
    return AppNotification(
      id: json['id'] as String,
      userId: json['userId'] as String,
      bookingId: json['bookingId'] as String?,
      type: json['type'] as String? ?? '',
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
      actionUrl: json['actionUrl'] as String?,
      isRead: json['isRead'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      readAt: parseOpt('readAt'),
      expiresAt: parseOpt('expiresAt'),
    );
  }
}