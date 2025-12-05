import 'package:shared_preferences/shared_preferences.dart';

/// Service for managing app preferences using SharedPreferences.
/// Handles user settings, notification preferences, and app configuration.
class PreferencesService {
  static SharedPreferences? _prefs;
  
  // Keys for stored preferences
  static const String _keyNotificationsEnabled = 'notifications_enabled';
  static const String _keyFeedingNotifications = 'feeding_notifications';
  static const String _keyCatDetectionNotifications = 'cat_detection_notifications';
  static const String _keyDefaultPortionSize = 'default_portion_size';
  static const String _keyUserName = 'user_name';
  static const String _keyUserEmail = 'user_email';
  static const String _keyIsLoggedIn = 'is_logged_in';
  static const String _keyLastFeederId = 'last_feeder_id';
  static const String _keyCameraStreamUrl = 'camera_stream_url';
  static const String _keyThemeMode = 'theme_mode';
  
  /// Initialize SharedPreferences
  static Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }
  
  /// Get SharedPreferences instance
  static SharedPreferences get prefs {
    if (_prefs == null) {
      throw Exception('PreferencesService not initialized. Call initialize() first.');
    }
    return _prefs!;
  }
  
  // --- Notification Settings ---
  
  static bool get notificationsEnabled => prefs.getBool(_keyNotificationsEnabled) ?? true;
  static set notificationsEnabled(bool value) => prefs.setBool(_keyNotificationsEnabled, value);
  
  static bool get feedingNotifications => prefs.getBool(_keyFeedingNotifications) ?? true;
  static set feedingNotifications(bool value) => prefs.setBool(_keyFeedingNotifications, value);
  
  static bool get catDetectionNotifications => prefs.getBool(_keyCatDetectionNotifications) ?? true;
  static set catDetectionNotifications(bool value) => prefs.setBool(_keyCatDetectionNotifications, value);
  
  // --- Feeder Settings ---
  
  static double get defaultPortionSize => prefs.getDouble(_keyDefaultPortionSize) ?? 50.0;
  static set defaultPortionSize(double value) => prefs.setDouble(_keyDefaultPortionSize, value);
  
  static String? get lastFeederId => prefs.getString(_keyLastFeederId);
  static set lastFeederId(String? value) {
    if (value != null) {
      prefs.setString(_keyLastFeederId, value);
    } else {
      prefs.remove(_keyLastFeederId);
    }
  }
  
  static String get cameraStreamUrl => prefs.getString(_keyCameraStreamUrl) ?? 'rtsp://192.168.1.100:8554/live';
  static set cameraStreamUrl(String value) => prefs.setString(_keyCameraStreamUrl, value);
  
  // --- User Info (for offline mode) ---
  
  static String? get userName => prefs.getString(_keyUserName);
  static set userName(String? value) {
    if (value != null) {
      prefs.setString(_keyUserName, value);
    } else {
      prefs.remove(_keyUserName);
    }
  }
  
  static String? get userEmail => prefs.getString(_keyUserEmail);
  static set userEmail(String? value) {
    if (value != null) {
      prefs.setString(_keyUserEmail, value);
    } else {
      prefs.remove(_keyUserEmail);
    }
  }
  
  static bool get isLoggedIn => prefs.getBool(_keyIsLoggedIn) ?? false;
  static set isLoggedIn(bool value) => prefs.setBool(_keyIsLoggedIn, value);
  
  // --- App Settings ---
  
  static String get themeMode => prefs.getString(_keyThemeMode) ?? 'light';
  static set themeMode(String value) => prefs.setString(_keyThemeMode, value);
  
  // --- Clear All ---
  
  static Future<void> clearAll() async {
    await prefs.clear();
  }
  
  static Future<void> clearUserData() async {
    await prefs.remove(_keyUserName);
    await prefs.remove(_keyUserEmail);
    await prefs.remove(_keyIsLoggedIn);
    await prefs.remove(_keyLastFeederId);
  }
}

