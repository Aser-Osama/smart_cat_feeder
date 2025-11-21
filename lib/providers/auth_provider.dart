import 'package:flutter/material.dart';

class AuthProvider with ChangeNotifier {
  bool _isAuthenticated = false;
  String? _userName;
  String? _userEmail;
  
  bool get isAuthenticated => _isAuthenticated;
  String? get userName => _userName;
  String? get userEmail => _userEmail;
  
  // Mock login function (Phase 1)
  Future<bool> login(String email, String password) async {
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 2));
    
    // Mock authentication - In Phase 2, integrate with Firebase
    if (email.isNotEmpty && password.length >= 6) {
      _isAuthenticated = true;
      _userEmail = email;
      _userName = email.split('@')[0];
      notifyListeners();
      return true;
    }
    return false;
  }
  
  // Mock register function (Phase 1)
  Future<bool> register(String name, String email, String password) async {
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 2));
    
    // Mock registration
    if (name.isNotEmpty && email.isNotEmpty && password.length >= 6) {
      _isAuthenticated = true;
      _userName = name;
      _userEmail = email;
      notifyListeners();
      return true;
    }
    return false;
  }
  
  // Logout function
  Future<void> logout() async {
    _isAuthenticated = false;
    _userName = null;
    _userEmail = null;
    notifyListeners();
  }
}

