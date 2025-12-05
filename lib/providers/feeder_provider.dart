import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/feeding_log.dart';
import '../models/schedule.dart';
import '../services/firebase_service.dart';
import '../services/preferences_service.dart';
import '../services/notification_service.dart';

/// Provider for feeder state and operations.
/// Uses Firestore when available, falls back to local storage otherwise.
class FeederProvider with ChangeNotifier {
  bool _isFeeding = false;
  bool _isLoading = false;
  List<FeedingLog> _feedingHistory = [];
  List<FeedingSchedule> _schedules = [];
  bool _catDetected = false;
  double _foodLevel = 75.0; // percentage
  String? _errorMessage;
  
  bool get isFeeding => _isFeeding;
  bool get isLoading => _isLoading;
  List<FeedingLog> get feedingHistory => _feedingHistory;
  List<FeedingSchedule> get schedules => _schedules;
  bool get catDetected => _catDetected;
  double get foodLevel => _foodLevel;
  String? get errorMessage => _errorMessage;
  
  FeederProvider() {
    _initializeData();
  }
  
  /// Initialize data from Firestore or local storage
  Future<void> _initializeData() async {
    _isLoading = true;
    notifyListeners();
    
    if (FirebaseService.isOfflineMode) {
      _initializeMockData();
    } else {
      await _loadFromFirestore();
    }
    
    _isLoading = false;
    notifyListeners();
  }
  
  /// Load data from Firestore
  Future<void> _loadFromFirestore() async {
    try {
      final userId = FirebaseService.currentUserId;
      if (userId == null) {
        _initializeMockData();
        return;
      }
      
      final firestore = FirebaseService.firestore!;
      
      // Load feeding history
      final logsSnapshot = await firestore
          .collection('users')
          .doc(userId)
          .collection('feeding_logs')
          .orderBy('timestamp', descending: true)
          .limit(50)
          .get();
      
      _feedingHistory = logsSnapshot.docs
          .map((doc) => FeedingLog.fromFirestore(doc))
          .toList();
      
      // Load schedules
      final schedulesSnapshot = await firestore
          .collection('users')
          .doc(userId)
          .collection('schedules')
          .get();
      
      _schedules = schedulesSnapshot.docs
          .map((doc) => FeedingSchedule.fromMap({...doc.data(), 'id': doc.id}))
          .toList();
      
      if (_schedules.isEmpty) {
        _initializeDefaultSchedules();
      }
      
      // Load feeder status
      final feederDoc = await firestore
          .collection('users')
          .doc(userId)
          .collection('feeder')
          .doc('status')
          .get();
      
      if (feederDoc.exists) {
        final data = feederDoc.data()!;
        _foodLevel = (data['foodLevel'] ?? 75.0).toDouble();
        _catDetected = data['catDetected'] ?? false;
      }
      
    } catch (e) {
      debugPrint('Error loading from Firestore: $e');
      _initializeMockData();
    }
  }
  
  /// Initialize with mock data for offline mode
  void _initializeMockData() {
    _feedingHistory = [
      FeedingLog(
        id: '1',
        timestamp: DateTime.now().subtract(const Duration(hours: 2)),
        amount: 50.0,
        type: FeedingType.manual,
        success: true,
      ),
      FeedingLog(
        id: '2',
        timestamp: DateTime.now().subtract(const Duration(hours: 8)),
        amount: 50.0,
        type: FeedingType.scheduled,
        success: true,
        scheduleName: 'Morning Feeding',
      ),
      FeedingLog(
        id: '3',
        timestamp: DateTime.now().subtract(const Duration(days: 1)),
        amount: 50.0,
        type: FeedingType.scheduled,
        success: true,
        scheduleName: 'Evening Feeding',
      ),
      FeedingLog(
        id: '4',
        timestamp: DateTime.now().subtract(const Duration(days: 1, hours: 8)),
        amount: 50.0,
        type: FeedingType.manual,
        success: true,
      ),
    ];
    
    _initializeDefaultSchedules();
  }
  
  /// Initialize default feeding schedules
  void _initializeDefaultSchedules() {
    _schedules = [
      FeedingSchedule(
        id: 'default_1',
        name: 'Morning Feeding',
        time: const TimeOfDay(hour: 8, minute: 0),
        amount: 50,
        isActive: true,
        weekdays: [1, 2, 3, 4, 5, 6, 7],
        createdAt: DateTime.now(),
      ),
      FeedingSchedule(
        id: 'default_2',
        name: 'Evening Feeding',
        time: const TimeOfDay(hour: 18, minute: 0),
        amount: 50,
        isActive: true,
        weekdays: [1, 2, 3, 4, 5, 6, 7],
        createdAt: DateTime.now(),
      ),
    ];
  }
  
  /// Trigger immediate feeding
  Future<bool> feedNow({double? amount}) async {
    if (_isFeeding) return false;
    
    _isFeeding = true;
    _errorMessage = null;
    notifyListeners();
    
    final feedAmount = amount ?? PreferencesService.defaultPortionSize;
    
    try {
      // Simulate feeding process (or send command to IoT device)
      await Future.delayed(const Duration(seconds: 3));
      
      // Create new log entry
      final newLog = FeedingLog(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        timestamp: DateTime.now(),
        amount: feedAmount,
        type: FeedingType.manual,
        success: true,
      );
      
      // Save to Firestore if available
      if (!FirebaseService.isOfflineMode && FirebaseService.currentUserId != null) {
        await _saveLogToFirestore(newLog);
        await _updateFeederStatus();
      }
      
      // Update local state
      _feedingHistory.insert(0, newLog);
      _foodLevel = (_foodLevel - 5).clamp(0, 100);
      _isFeeding = false;
      notifyListeners();
      
      // Show notification
      await NotificationService.showManualFeedingNotification(feedAmount);
      
      return true;
    } catch (e) {
      _errorMessage = 'Feeding failed: $e';
      _isFeeding = false;
      notifyListeners();
      return false;
    }
  }
  
  /// Save feeding log to Firestore
  Future<void> _saveLogToFirestore(FeedingLog log) async {
    final userId = FirebaseService.currentUserId;
    if (userId == null) return;
    
    await FirebaseService.firestore!
        .collection('users')
        .doc(userId)
        .collection('feeding_logs')
        .doc(log.id)
        .set(log.toFirestore());
  }
  
  /// Update feeder status in Firestore
  Future<void> _updateFeederStatus() async {
    final userId = FirebaseService.currentUserId;
    if (userId == null) return;
    
    await FirebaseService.firestore!
        .collection('users')
        .doc(userId)
        .collection('feeder')
        .doc('status')
        .set({
          'foodLevel': _foodLevel,
          'catDetected': _catDetected,
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }
  
  // --- Schedule Management ---
  
  /// Add a new feeding schedule
  Future<bool> addSchedule(FeedingSchedule schedule) async {
    try {
      final newSchedule = schedule.copyWith(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        createdAt: DateTime.now(),
      );
      
      if (!FirebaseService.isOfflineMode && FirebaseService.currentUserId != null) {
        await FirebaseService.firestore!
            .collection('users')
            .doc(FirebaseService.currentUserId)
            .collection('schedules')
            .doc(newSchedule.id)
            .set(newSchedule.toMap());
      }
      
      _schedules.add(newSchedule);
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to add schedule: $e';
      notifyListeners();
      return false;
    }
  }
  
  /// Update an existing schedule
  Future<bool> updateSchedule(FeedingSchedule schedule) async {
    try {
      final updatedSchedule = schedule.copyWith(updatedAt: DateTime.now());
      
      if (!FirebaseService.isOfflineMode && FirebaseService.currentUserId != null) {
        await FirebaseService.firestore!
            .collection('users')
            .doc(FirebaseService.currentUserId)
            .collection('schedules')
            .doc(schedule.id)
            .update(updatedSchedule.toMap());
      }
      
      final index = _schedules.indexWhere((s) => s.id == schedule.id);
      if (index != -1) {
        _schedules[index] = updatedSchedule;
        notifyListeners();
      }
      return true;
    } catch (e) {
      _errorMessage = 'Failed to update schedule: $e';
      notifyListeners();
      return false;
    }
  }
  
  /// Toggle schedule active status
  Future<bool> toggleScheduleActive(String scheduleId) async {
    final index = _schedules.indexWhere((s) => s.id == scheduleId);
    if (index == -1) return false;
    
    final schedule = _schedules[index];
    return await updateSchedule(schedule.copyWith(isActive: !schedule.isActive));
  }
  
  /// Delete a schedule
  Future<bool> deleteSchedule(String scheduleId) async {
    try {
      if (!FirebaseService.isOfflineMode && FirebaseService.currentUserId != null) {
        await FirebaseService.firestore!
            .collection('users')
            .doc(FirebaseService.currentUserId)
            .collection('schedules')
            .doc(scheduleId)
            .delete();
      }
      
      _schedules.removeWhere((s) => s.id == scheduleId);
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to delete schedule: $e';
      notifyListeners();
      return false;
    }
  }
  
  // --- Status Updates ---
  
  /// Update cat detection status (from IoT sensor)
  void updateCatDetection(bool detected) {
    if (_catDetected != detected) {
      _catDetected = detected;
      notifyListeners();
      
      if (detected) {
        NotificationService.showCatDetectedNotification();
      }
    }
  }
  
  /// Update food level (from IoT sensor)
  void updateFoodLevel(double level) {
    _foodLevel = level.clamp(0, 100);
    notifyListeners();
  }
  
  // --- Statistics ---
  
  /// Get today's feeding count
  int getTodayFeedingCount() {
    return _feedingHistory.where((log) => log.isToday).length;
  }
  
  /// Get this week's feeding count
  int getWeekFeedingCount() {
    return _feedingHistory.where((log) => log.isThisWeek).length;
  }
  
  /// Get total amount dispensed
  double getTotalAmountDispensed() {
    return _feedingHistory.fold(0.0, (total, log) => total + log.amount);
  }
  
  /// Get last feeding time
  DateTime? getLastFeedingTime() {
    if (_feedingHistory.isEmpty) return null;
    return _feedingHistory.first.timestamp;
  }
  
  /// Get active schedules count
  int get activeSchedulesCount => _schedules.where((s) => s.isActive).length;
  
  /// Refresh data from server
  Future<void> refreshData() async {
    await _initializeData();
  }
}
