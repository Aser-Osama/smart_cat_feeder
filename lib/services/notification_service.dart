import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'preferences_service.dart';
import 'firebase_service.dart';

/// Service for handling local and push notifications.
/// Phase 2: Local notifications for feeding events.
/// Phase 3: FCM integration for remote push notifications from Cloud Functions.
class NotificationService {
  static bool _initialized = false;
  static String? _fcmToken;
  
  // Notification channels/categories
  static const String feedingChannel = 'feeding_notifications';
  static const String catDetectionChannel = 'cat_detection_notifications';
  static const String scheduleChannel = 'schedule_notifications';
  
  /// Get current FCM token
  static String? get fcmToken => _fcmToken;
  
  /// Initialize notification service
  static Future<void> initialize() async {
    if (_initialized) return;
    
    // Initialize FCM if Firebase is available
    if (!FirebaseService.isOfflineMode) {
      await _initializeFCM();
    }
    
    _initialized = true;
    debugPrint('✅ Notification service initialized');
  }
  
  /// Initialize Firebase Cloud Messaging
  static Future<void> _initializeFCM() async {
    try {
      final messaging = FirebaseMessaging.instance;
      
      // Request permission for notifications
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      
      debugPrint('📱 FCM Permission: ${settings.authorizationStatus}');
      
      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        
        // Get FCM token
        _fcmToken = await messaging.getToken();
        debugPrint('📱 FCM Token: $_fcmToken');
        
        // Listen for token refresh
        messaging.onTokenRefresh.listen((newToken) {
          _fcmToken = newToken;
          _saveTokenToFirestore(newToken);
          debugPrint('📱 FCM Token refreshed: $newToken');
        });
        
        // Handle foreground messages
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
        
        // Handle background/terminated messages
        FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);
        
        // Check if app was opened from a notification
        final initialMessage = await messaging.getInitialMessage();
        if (initialMessage != null) {
          _handleMessageOpenedApp(initialMessage);
        }
      }
    } catch (e) {
      debugPrint('❌ FCM initialization error: $e');
    }
  }
  
  /// Save FCM token to Firestore for the current user
  static Future<void> saveTokenForUser(String userId) async {
    if (_fcmToken == null || FirebaseService.isOfflineMode) return;
    
    await _saveTokenToFirestore(_fcmToken!, userId: userId);
  }
  
  /// Internal method to save token to Firestore
  static Future<void> _saveTokenToFirestore(String token, {String? userId}) async {
    final uid = userId ?? FirebaseService.currentUserId;
    if (uid == null) return;
    
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('fcm_tokens')
          .doc(token)
          .set({
            'token': token,
            'platform': defaultTargetPlatform.toString(),
            'createdAt': FieldValue.serverTimestamp(),
            'lastUpdated': FieldValue.serverTimestamp(),
          });
      
      debugPrint('✅ FCM token saved to Firestore');
    } catch (e) {
      debugPrint('❌ Error saving FCM token: $e');
    }
  }
  
  /// Remove FCM token from Firestore (on logout)
  static Future<void> removeTokenForUser(String userId) async {
    if (_fcmToken == null || FirebaseService.isOfflineMode) return;
    
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('fcm_tokens')
          .doc(_fcmToken)
          .delete();
      
      debugPrint('✅ FCM token removed from Firestore');
    } catch (e) {
      debugPrint('❌ Error removing FCM token: $e');
    }
  }
  
  /// Handle foreground FCM messages
  static void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('📱 Foreground message: ${message.notification?.title}');
    
    // Show local notification for foreground messages
    if (message.notification != null) {
      showFeedingNotification(
        title: message.notification!.title ?? 'Smart Cat Feeder',
        body: message.notification!.body ?? '',
        data: message.data,
      );
    }
  }
  
  /// Handle when user taps on a notification
  static void _handleMessageOpenedApp(RemoteMessage message) {
    debugPrint('📱 Notification tapped: ${message.data}');
    
    // Handle navigation based on notification type
    final type = message.data['type'];
    switch (type) {
      case 'scheduled_feeding':
      case 'manual_feeding':
        // Navigate to history screen
        debugPrint('Should navigate to history');
        break;
      case 'low_food_alert':
        // Navigate to home screen
        debugPrint('Should navigate to home');
        break;
      case 'schedule_created':
        // Navigate to schedules screen
        debugPrint('Should navigate to schedules');
        break;
    }
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

