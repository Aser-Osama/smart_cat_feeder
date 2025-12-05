import 'package:flutter/foundation.dart';
import 'preferences_service.dart';

/// Service for handling local and push notifications.
/// Phase 2: Local notifications for feeding events.
/// Future: FCM integration for remote push notifications.
class NotificationService {
  static bool _initialized = false;
  
  // Notification channels/categories
  static const String feedingChannel = 'feeding_notifications';
  static const String catDetectionChannel = 'cat_detection_notifications';
  static const String scheduleChannel = 'schedule_notifications';
  
  /// Initialize notification service
  static Future<void> initialize() async {
    if (_initialized) return;
    
    // TODO: Initialize flutter_local_notifications when added to dependencies
    // For now, we'll use a simpler approach with just logging
    
    _initialized = true;
    debugPrint('✅ Notification service initialized');
  }
  
  /// Show a feeding complete notification
  static Future<void> showFeedingNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    if (!PreferencesService.notificationsEnabled) return;
    if (!PreferencesService.feedingNotifications) return;
    
    // TODO: Show actual local notification
    debugPrint('🔔 Notification: $title - $body');
    
    // For now, this is a placeholder. In a full implementation:
    // await FlutterLocalNotificationsPlugin().show(
    //   id,
    //   title,
    //   body,
    //   notificationDetails,
    //   payload: jsonEncode(data),
    // );
  }
  
  /// Show a cat detection notification
  static Future<void> showCatDetectedNotification() async {
    if (!PreferencesService.notificationsEnabled) return;
    if (!PreferencesService.catDetectionNotifications) return;
    
    await showFeedingNotification(
      title: 'Cat Detected! 🐱',
      body: 'Your cat is at the feeder.',
      data: {'type': 'cat_detection'},
    );
  }
  
  /// Show a scheduled feeding notification
  static Future<void> showScheduledFeedingNotification(String scheduleName) async {
    if (!PreferencesService.notificationsEnabled) return;
    if (!PreferencesService.feedingNotifications) return;
    
    await showFeedingNotification(
      title: 'Scheduled Feeding Complete ⏰',
      body: '$scheduleName has been dispensed.',
      data: {'type': 'scheduled_feeding', 'schedule': scheduleName},
    );
  }
  
  /// Show a manual feeding notification
  static Future<void> showManualFeedingNotification(double amount) async {
    if (!PreferencesService.notificationsEnabled) return;
    if (!PreferencesService.feedingNotifications) return;
    
    await showFeedingNotification(
      title: 'Feeding Complete! 🎉',
      body: '${amount.toInt()}g of food has been dispensed.',
      data: {'type': 'manual_feeding', 'amount': amount},
    );
  }
  
  /// Cancel all notifications
  static Future<void> cancelAll() async {
    // TODO: Cancel all local notifications
    debugPrint('🔕 All notifications cancelled');
  }
}

