import 'package:flutter/material.dart';
import '../models/feeding_log.dart';

class FeederProvider with ChangeNotifier {
  bool _isFeeding = false;
  List<FeedingLog> _feedingHistory = [];
  bool _catDetected = false;
  double _foodLevel = 75.0; // percentage
  
  bool get isFeeding => _isFeeding;
  List<FeedingLog> get feedingHistory => _feedingHistory;
  bool get catDetected => _catDetected;
  double get foodLevel => _foodLevel;
  
  FeederProvider() {
    _initializeMockData();
  }
  
  // Initialize with mock data for Phase 1
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
      ),
      FeedingLog(
        id: '3',
        timestamp: DateTime.now().subtract(const Duration(days: 1)),
        amount: 50.0,
        type: FeedingType.scheduled,
        success: true,
      ),
      FeedingLog(
        id: '4',
        timestamp: DateTime.now().subtract(const Duration(days: 1, hours: 8)),
        amount: 50.0,
        type: FeedingType.manual,
        success: true,
      ),
    ];
  }
  
  // Feed now function (Phase 1: Mock, Phase 2: Firebase integration)
  Future<bool> feedNow() async {
    if (_isFeeding) return false;
    
    _isFeeding = true;
    notifyListeners();
    
    // Simulate feeding process
    await Future.delayed(const Duration(seconds: 3));
    
    // Add to history
    final newLog = FeedingLog(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      timestamp: DateTime.now(),
      amount: 50.0,
      type: FeedingType.manual,
      success: true,
    );
    
    _feedingHistory.insert(0, newLog);
    _foodLevel = (_foodLevel - 5).clamp(0, 100);
    _isFeeding = false;
    notifyListeners();
    
    return true;
  }
  
  // Simulate cat detection
  void simulateCatDetection(bool detected) {
    _catDetected = detected;
    notifyListeners();
  }
  
  // Get today's feeding count
  int getTodayFeedingCount() {
    final today = DateTime.now();
    return _feedingHistory.where((log) {
      return log.timestamp.year == today.year &&
             log.timestamp.month == today.month &&
             log.timestamp.day == today.day;
    }).length;
  }
  
  // Get last feeding time
  DateTime? getLastFeedingTime() {
    if (_feedingHistory.isEmpty) return null;
    return _feedingHistory.first.timestamp;
  }
}

