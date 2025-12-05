import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firebase_service.dart';
import '../services/preferences_service.dart';

/// Callback type for authentication state changes
typedef AuthStateCallback = void Function(String? userId);

/// Authentication provider with Firebase Auth integration.
/// Falls back to local/offline mode when Firebase is not configured.
class AuthProvider with ChangeNotifier {
  bool _isAuthenticated = false;
  bool _isLoading = false;
  String? _userName;
  String? _userEmail;
  String? _userId;
  String? _errorMessage;
  
  /// Callback to notify when user auth state changes
  AuthStateCallback? onAuthStateChanged;
  
  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  String? get userName => _userName;
  String? get userEmail => _userEmail;
  String? get userId => _userId;
  String? get errorMessage => _errorMessage;
  
  AuthProvider() {
    _checkAuthState();
  }
  
  /// Set the callback for auth state changes
  void setAuthStateCallback(AuthStateCallback callback) {
    onAuthStateChanged = callback;
  }
  
  /// Notify listeners about auth state change
  void _notifyAuthStateChange() {
    onAuthStateChanged?.call(_userId);
  }
  
  /// Check if user is already authenticated (on app start)
  Future<void> _checkAuthState() async {
    if (FirebaseService.isOfflineMode) {
      // Check SharedPreferences for offline login state
      _isAuthenticated = PreferencesService.isLoggedIn;
      if (_isAuthenticated) {
        _userEmail = PreferencesService.userEmail;
        _userName = PreferencesService.userName;
        _userId = 'offline_user';
      }
    } else {
      // Check Firebase Auth state
      final user = FirebaseService.auth?.currentUser;
      if (user != null) {
        _isAuthenticated = true;
        _userEmail = user.email;
        _userId = user.uid;
        
        // Try to get display name from Auth first
        _userName = user.displayName;
        
        // If not available, fetch from Firestore
        if (_userName == null || _userName!.isEmpty) {
          _userName = await _fetchUserNameFromFirestore(user.uid);
        }
        
        // Final fallback to email prefix
        _userName ??= user.email?.split('@')[0];
      }
    }
    notifyListeners();
    
    // Notify FeederProvider about initial auth state
    _notifyAuthStateChange();
  }
  
  /// Fetch user name from Firestore
  Future<String?> _fetchUserNameFromFirestore(String uid) async {
    try {
      final doc = await FirebaseService.firestore?.collection('users').doc(uid).get();
      if (doc != null && doc.exists) {
        return doc.data()?['displayName'] as String?;
      }
    } catch (e) {
      debugPrint('Could not fetch user name from Firestore: $e');
    }
    return null;
  }
  
  /// Login with email and password
  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    
    try {
      if (FirebaseService.isOfflineMode) {
        // Offline mode: Validate locally
        return await _loginOffline(email, password);
      } else {
        // Firebase mode: Use Firebase Auth
        return await _loginWithFirebase(email, password);
      }
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  /// Login using Firebase Authentication
  Future<bool> _loginWithFirebase(String email, String password) async {
    try {
      final credential = await FirebaseService.auth!.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      final user = credential.user;
      if (user != null) {
        // Reload user to get latest profile data
        await user.reload();
        final refreshedUser = FirebaseService.auth!.currentUser;
        
        _isAuthenticated = true;
        _userEmail = refreshedUser?.email ?? user.email;
        _userId = refreshedUser?.uid ?? user.uid;
        
        // Try to get display name, fallback to Firestore, then email prefix
        _userName = refreshedUser?.displayName;
        if (_userName == null || _userName!.isEmpty) {
          _userName = await _fetchUserNameFromFirestore(_userId!);
        }
        _userName ??= _userEmail?.split('@')[0];
        
        _isLoading = false;
        notifyListeners();
        _notifyAuthStateChange(); // Notify FeederProvider to load user data
        return true;
      }
      
      _errorMessage = 'Login failed. Please try again.';
      _isLoading = false;
      notifyListeners();
      return false;
    } on FirebaseAuthException catch (e) {
      _errorMessage = _getAuthErrorMessage(e.code);
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      // Handle Pigeon type cast errors and other unexpected exceptions
      // Check if authentication actually succeeded despite the error
      final user = FirebaseService.auth?.currentUser;
      if (user != null && user.email == email) {
        _isAuthenticated = true;
        _userEmail = user.email;
        _userId = user.uid;
        _userName = user.displayName;
        if (_userName == null || _userName!.isEmpty) {
          _userName = await _fetchUserNameFromFirestore(_userId!);
        }
        _userName ??= _userEmail?.split('@')[0];
        _isLoading = false;
        notifyListeners();
        _notifyAuthStateChange(); // Notify FeederProvider to load user data
        return true;
      }
      
      _errorMessage = 'Login failed: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  /// Offline login (for development/demo mode)
  Future<bool> _loginOffline(String email, String password) async {
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 1));
    
    // Basic validation for offline mode
    if (email.isNotEmpty && password.length >= 6) {
      _isAuthenticated = true;
      _userEmail = email;
      _userName = email.split('@')[0];
      _userId = 'offline_user';
      
      // Save to preferences
      PreferencesService.isLoggedIn = true;
      PreferencesService.userEmail = email;
      PreferencesService.userName = _userName;
      
      _isLoading = false;
      notifyListeners();
      _notifyAuthStateChange(); // Notify FeederProvider
      return true;
    }
    
    _errorMessage = 'Invalid email or password';
    _isLoading = false;
    notifyListeners();
    return false;
  }
  
  /// Register new user with email and password
  Future<bool> register(String name, String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    
    try {
      if (FirebaseService.isOfflineMode) {
        return await _registerOffline(name, email, password);
      } else {
        return await _registerWithFirebase(name, email, password);
      }
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  /// Register using Firebase Authentication
  Future<bool> _registerWithFirebase(String name, String email, String password) async {
    try {
      final credential = await FirebaseService.auth!.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      final user = credential.user;
      if (user != null) {
        // Update display name in Firebase Auth
        try {
          await user.updateDisplayName(name);
          await user.reload(); // Reload to persist the display name
        } catch (e) {
          debugPrint('Warning: Could not update display name in Auth: $e');
        }
        
        // Store user profile in Firestore for reliable retrieval
        try {
          await FirebaseService.firestore?.collection('users').doc(user.uid).set({
            'displayName': name,
            'email': email,
            'createdAt': DateTime.now().toIso8601String(),
          }, SetOptions(merge: true));
        } catch (e) {
          debugPrint('Warning: Could not save user profile to Firestore: $e');
        }
        
        _isAuthenticated = true;
        _userEmail = user.email;
        _userName = name;
        _userId = user.uid;
        _isLoading = false;
        notifyListeners();
        _notifyAuthStateChange(); // Notify FeederProvider to initialize user data
        return true;
      }
      
      _errorMessage = 'Registration failed. Please try again.';
      _isLoading = false;
      notifyListeners();
      return false;
    } on FirebaseAuthException catch (e) {
      _errorMessage = _getAuthErrorMessage(e.code);
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      // Handle Pigeon type cast errors - check if registration actually succeeded
      final user = FirebaseService.auth?.currentUser;
      if (user != null && user.email == email) {
        // Registration succeeded, save profile data
        try {
          await user.updateDisplayName(name);
          await user.reload();
        } catch (_) {}
        
        try {
          await FirebaseService.firestore?.collection('users').doc(user.uid).set({
            'displayName': name,
            'email': email,
            'createdAt': DateTime.now().toIso8601String(),
          }, SetOptions(merge: true));
        } catch (_) {}
        
        _isAuthenticated = true;
        _userEmail = user.email;
        _userName = name;
        _userId = user.uid;
        _isLoading = false;
        notifyListeners();
        _notifyAuthStateChange(); // Notify FeederProvider to initialize user data
        return true;
      }
      
      _errorMessage = 'Registration failed: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  /// Offline registration (for development/demo mode)
  Future<bool> _registerOffline(String name, String email, String password) async {
    await Future.delayed(const Duration(seconds: 1));
    
    if (name.isNotEmpty && email.isNotEmpty && password.length >= 6) {
      _isAuthenticated = true;
      _userName = name;
      _userEmail = email;
      _userId = 'offline_user';
      
      // Save to preferences
      PreferencesService.isLoggedIn = true;
      PreferencesService.userEmail = email;
      PreferencesService.userName = name;
      
      _isLoading = false;
      notifyListeners();
      _notifyAuthStateChange(); // Notify FeederProvider
      return true;
    }
    
    _errorMessage = 'Please fill in all fields correctly';
    _isLoading = false;
    notifyListeners();
    return false;
  }
  
  /// Send password reset email
  Future<bool> resetPassword(String email) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    
    try {
      if (FirebaseService.isOfflineMode) {
        await Future.delayed(const Duration(seconds: 1));
        _isLoading = false;
        notifyListeners();
        return true; // Simulate success in offline mode
      }
      
      await FirebaseService.auth!.sendPasswordResetEmail(email: email);
      _isLoading = false;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      _errorMessage = _getAuthErrorMessage(e.code);
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  /// Logout the current user
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      if (!FirebaseService.isOfflineMode) {
        await FirebaseService.auth?.signOut();
      }
      
      // Clear local state
      await PreferencesService.clearUserData();
      
      _isAuthenticated = false;
      _userName = null;
      _userEmail = null;
      _userId = null;
      _isLoading = false;
      notifyListeners();
      _notifyAuthStateChange(); // Notify FeederProvider to clear data
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }
  
  /// Get user-friendly error message from Firebase error code
  String _getAuthErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'operation-not-allowed':
        return 'Email/password sign in is not enabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'invalid-credential':
        return 'Invalid email or password.';
      default:
        return 'Authentication error: $code';
    }
  }
}
