import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../firebase_options.dart';

/// Firebase service for initializing and managing Firebase connections.
/// Supports both real Firebase and demo/offline mode for development.
class FirebaseService {
  static bool _initialized = false;
  static bool _useOfflineMode = false;
  
  static bool get isInitialized => _initialized;
  static bool get isOfflineMode => _useOfflineMode;
  
  /// Initialize Firebase with fallback to offline mode if not configured
  static Future<void> initialize() async {
    if (_initialized) return;
    
    try {
      // Try to get platform-specific Firebase options
      final options = DefaultFirebaseOptions.currentPlatform;
      await Firebase.initializeApp(options: options);
      _initialized = true;
      _useOfflineMode = false;
      
      // Enable Firestore offline persistence
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
      
      debugPrint('✅ Firebase initialized successfully');
    } catch (e) {
      // Firebase not configured - use offline/demo mode
      _initialized = true;
      _useOfflineMode = true;
      debugPrint('⚠️ Firebase not configured, using offline mode: $e');
    }
  }
  
  /// Get Firebase Auth instance (null if in offline mode)
  static FirebaseAuth? get auth {
    if (_useOfflineMode) return null;
    return FirebaseAuth.instance;
  }
  
  /// Get Firestore instance (null if in offline mode)
  static FirebaseFirestore? get firestore {
    if (_useOfflineMode) return null;
    return FirebaseFirestore.instance;
  }
  
  /// Check if a user is currently signed in
  static bool get isSignedIn {
    if (_useOfflineMode) return false;
    return FirebaseAuth.instance.currentUser != null;
  }
  
  /// Get current user ID
  static String? get currentUserId {
    if (_useOfflineMode) return null;
    return FirebaseAuth.instance.currentUser?.uid;
  }
  
  /// Get current user email
  static String? get currentUserEmail {
    if (_useOfflineMode) return null;
    return FirebaseAuth.instance.currentUser?.email;
  }
}

