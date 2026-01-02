import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/shelter_node.dart';
import '../models/alert.dart';
import '../models/color_calibration.dart';
import '../services/firebase_service.dart';

/// Provider for shelter monitoring state and operations.
/// Manages 4 nodes (W, X, Y, Z), alerts, and routing logs.
class ShelterProvider with ChangeNotifier {
  // Node data
  final Map<String, ShelterNode> _nodes = {};
  
  // Alerts
  List<ShelterAlert> _alerts = [];
  List<RoutingDecision> _routingLogs = [];
  
  // State
  bool _isLoading = false;
  String? _errorMessage;
  String? _currentUserId;
  
  // Firestore listeners
  final Map<String, StreamSubscription<DocumentSnapshot>> _nodeListeners = {};
  StreamSubscription<QuerySnapshot>? _alertsListener;
  StreamSubscription<QuerySnapshot>? _routingListener;
  
  // Demo mode data (when offline)
  bool _isDemoMode = false;
  
  // Getters
  Map<String, ShelterNode> get nodes => _nodes;
  List<ShelterNode> get nodeList => _nodes.values.toList()..sort((a, b) => a.nodeId.compareTo(b.nodeId));
  List<ShelterAlert> get alerts => _alerts;
  List<ShelterAlert> get unacknowledgedAlerts => _alerts.where((a) => !a.acknowledged).toList();
  List<ShelterAlert> get emptyPlateAlerts => _alerts.where(
    (a) => a.type == AlertType.emptyPlate && !a.acknowledged
  ).toList();
  List<RoutingDecision> get routingLogs => _routingLogs;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isDemoMode => _isDemoMode;
  
  // Node IDs
  static const List<String> nodeIds = ['W', 'X', 'Y', 'Z'];
  
  ShelterProvider() {
    _initializeNodes();
  }
  
  /// Initialize empty nodes
  void _initializeNodes() {
    for (final id in nodeIds) {
      _nodes[id] = ShelterNode(
        nodeId: id,
        displayName: 'Bowl $id',
        isOnline: false,
        plateStatus: PlateStatus.unknown,
      );
    }
  }
  
  /// Called when user authentication state changes
  Future<void> onUserChanged(String? userId) async {
    debugPrint('🔄 ShelterProvider.onUserChanged called with userId: $userId');
    if (_currentUserId == userId) {
      debugPrint('   → Same user, skipping');
      return;
    }
    
    _currentUserId = userId;
    debugPrint('   → New user, loading data...');
    
    if (userId == null) {
      _clearData();
    } else {
      await _loadData();
    }
  }
  
  /// Clear all data and listeners
  void _clearData() {
    // Cancel listeners
    for (final sub in _nodeListeners.values) {
      sub.cancel();
    }
    _nodeListeners.clear();
    _alertsListener?.cancel();
    _routingListener?.cancel();
    
    // Reset state
    _initializeNodes();
    _alerts = [];
    _routingLogs = [];
    _errorMessage = null;
    _isDemoMode = false;
    
    notifyListeners();
  }
  
  /// Load data from Firestore
  Future<void> _loadData() async {
    _isLoading = true;
    notifyListeners();
    
    if (FirebaseService.isOfflineMode) {
      _initializeDemoMode();
    } else {
      await _loadFromFirestore();
    }
    
    _isLoading = false;
    notifyListeners();
  }
  
  /// Initialize demo mode with simulated data
  void _initializeDemoMode() {
    _isDemoMode = true;
    
    _nodes['W'] = ShelterNode(
      nodeId: 'W',
      displayName: 'Bowl W',
      plateStatus: PlateStatus.filled,
      catPresent: false,
      batteryPercent: 85.0,
      rssi: -55,
      hopCount: 1,
      route: ['W', 'SINK'],
      lastUpdate: DateTime.now().subtract(const Duration(seconds: 30)),
      isOnline: true,
    );
    
    _nodes['X'] = ShelterNode(
      nodeId: 'X',
      displayName: 'Bowl X',
      plateStatus: PlateStatus.empty,
      catPresent: false,
      batteryPercent: 42.0,
      rssi: -72,
      hopCount: 2,
      route: ['X', 'W', 'SINK'],
      lastUpdate: DateTime.now().subtract(const Duration(seconds: 45)),
      isOnline: true,
    );
    
    _nodes['Y'] = ShelterNode(
      nodeId: 'Y',
      displayName: 'Bowl Y',
      plateStatus: PlateStatus.filled,
      catPresent: true,
      batteryPercent: 91.0,
      rssi: -48,
      hopCount: 1,
      route: ['Y', 'SINK'],
      lastUpdate: DateTime.now().subtract(const Duration(seconds: 15)),
      isOnline: true,
    );
    
    _nodes['Z'] = ShelterNode(
      nodeId: 'Z',
      displayName: 'Bowl Z',
      plateStatus: PlateStatus.unknown,
      catPresent: false,
      batteryPercent: 67.0,
      rssi: -80,
      hopCount: 2,
      route: ['Z', 'Y', 'SINK'],
      lastUpdate: DateTime.now().subtract(const Duration(minutes: 5)),
      isOnline: false,
    );
    
    // Demo alerts
    _alerts = [
      ShelterAlert(
        id: 'demo_alert_1',
        nodeId: 'X',
        type: AlertType.emptyPlate,
        severity: AlertSeverity.warning,
        timestamp: DateTime.now().subtract(const Duration(minutes: 10)),
        message: 'Empty plate at Bowl X - needs refill',
      ),
      ShelterAlert(
        id: 'demo_alert_2',
        nodeId: 'Z',
        type: AlertType.nodeOffline,
        severity: AlertSeverity.warning,
        timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
        message: 'Node Z has not reported in recently',
      ),
    ];
    
    debugPrint('🎮 Demo mode initialized with simulated data');
  }
  
  /// Load from Firestore with real-time listeners
  Future<void> _loadFromFirestore() async {
    try {
      final userId = FirebaseService.currentUserId;
      debugPrint('📡 _loadFromFirestore: userId=$userId, offlineMode=${FirebaseService.isOfflineMode}');
      if (userId == null) {
        debugPrint('   → No userId, falling back to demo mode');
        _initializeDemoMode();
        return;
      }
      
      _currentUserId = userId;
      final firestore = FirebaseService.firestore!;
      
      // DEBUG: Print user ID to help verify it matches the ESP's hardcoded USER_ID
      debugPrint('🔑 Setting up Firestore listeners for user: $userId');
      debugPrint('   → ESP hardcoded USER_ID should be: EyrwFFoBJ8TlVFepJvqdeooOBwA2');
      debugPrint('   → UIDs match: ${userId == "EyrwFFoBJ8TlVFepJvqdeooOBwA2"}');
      
      // Set up listeners for each node
      for (final nodeId in nodeIds) {
        final nodeRef = firestore
            .collection('users')
            .doc(userId)
            .collection('nodes')
            .doc(nodeId);
        
        _nodeListeners[nodeId] = nodeRef.snapshots().listen(
          (snapshot) async {
            if (snapshot.exists) {
              var node = ShelterNode.fromFirestore(snapshot);
              
              // Load calibration for this node
              try {
                final calibrationDoc = await firestore
                    .collection('shelter')
                    .doc('nodes')
                    .collection(nodeId)
                    .doc('calibration')
                    .get();
                
                if (calibrationDoc.exists) {
                  final calibrationData = calibrationDoc.data();
                  if (calibrationData != null) {
                    node = node.copyWith(
                      currentCalibration: ColorCalibration.fromJson(calibrationData),
                    );
                    debugPrint('📐 Node $nodeId calibration loaded: ${calibrationData['colorName']}');
                  }
                }
              } catch (e) {
                debugPrint('⚠️ Failed to load calibration for node $nodeId: $e');
              }
              
              _nodes[nodeId] = node;
              debugPrint('📡 Node $nodeId updated');
              notifyListeners();
            }
          },
          onError: (error) {
            debugPrint('❌ Error listening to node $nodeId: $error');
          },
        );
      }
      
      // Set up alerts listener
      final alertsRef = firestore
          .collection('users')
          .doc(userId)
          .collection('alerts')
          .orderBy('timestamp', descending: true)
          .limit(50);
      
      _alertsListener = alertsRef.snapshots().listen(
        (snapshot) {
          _alerts = snapshot.docs
              .map((doc) => ShelterAlert.fromFirestore(doc))
              .toList();
          debugPrint('🚨 Alerts updated: ${_alerts.length} alerts');
          notifyListeners();
          
          // Show notification for new unacknowledged alerts
          _checkForNewAlerts();
        },
        onError: (error) {
          debugPrint('❌ Error listening to alerts: $error');
        },
      );
      
      // Set up routing logs listener (last 20)
      final routingRef = firestore
          .collection('users')
          .doc(userId)
          .collection('routing_logs')
          .orderBy('timestamp', descending: true)
          .limit(20);
      
      _routingListener = routingRef.snapshots().listen(
        (snapshot) {
          _routingLogs = snapshot.docs
              .map((doc) => RoutingDecision.fromMap(doc.data()))
              .toList();
          debugPrint('🔀 Routing logs updated: ${_routingLogs.length} entries');
          notifyListeners();
        },
        onError: (error) {
          debugPrint('❌ Error listening to routing logs: $error');
        },
      );
      
      debugPrint('✅ Firestore listeners set up for user: $userId');
      
    } catch (e) {
      debugPrint('Error loading from Firestore: $e');
      _initializeDemoMode();
    }
  }
  
  /// Check for new alerts and show notification
  void _checkForNewAlerts() {
    final recentUnacked = _alerts.where((a) =>
      !a.acknowledged &&
      a.timestamp.isAfter(DateTime.now().subtract(const Duration(minutes: 1)))
    ).toList();
    
    for (final alert in recentUnacked) {
      if (alert.type == AlertType.emptyPlate) {
        // Note: Local notifications are handled by FCM push from cloud functions
        // This is a debug log for development
        debugPrint('🍽️ New alert: ${alert.title} - ${alert.message ?? alert.defaultMessage}');
      }
    }
  }
  
  /// Acknowledge an alert
  Future<bool> acknowledgeAlert(String alertId) async {
    try {
      final userId = FirebaseService.currentUserId;
      
      if (!FirebaseService.isOfflineMode && userId != null) {
        await FirebaseService.firestore!
            .collection('users')
            .doc(userId)
            .collection('alerts')
            .doc(alertId)
            .update({
              'acknowledged': true,
              'acknowledgedAt': FieldValue.serverTimestamp(),
            });
      }
      
      // Update local state
      final index = _alerts.indexWhere((a) => a.id == alertId);
      if (index != -1) {
        _alerts[index] = _alerts[index].copyWith(
          acknowledged: true,
          acknowledgedAt: DateTime.now(),
        );
        notifyListeners();
      }
      
      return true;
    } catch (e) {
      _errorMessage = 'Failed to acknowledge alert: $e';
      notifyListeners();
      return false;
    }
  }
  
  /// Acknowledge all alerts for a node
  Future<bool> acknowledgeAllForNode(String nodeId) async {
    try {
      final toAck = _alerts.where(
        (a) => a.nodeId == nodeId && !a.acknowledged
      ).toList();
      
      for (final alert in toAck) {
        await acknowledgeAlert(alert.id);
      }
      
      return true;
    } catch (e) {
      _errorMessage = 'Failed to acknowledge alerts: $e';
      notifyListeners();
      return false;
    }
  }
  
  /// Get node by ID
  ShelterNode? getNode(String nodeId) => _nodes[nodeId];
  
  /// Get alerts for a specific node
  List<ShelterAlert> getAlertsForNode(String nodeId) {
    return _alerts.where((a) => a.nodeId == nodeId).toList();
  }
  
  /// Get statistics
  AlertStats get alertStats => AlertStats.fromAlerts(_alerts);
  
  /// Get count of online nodes
  int get onlineNodeCount => _nodes.values.where((n) => n.isOnline).length;
  
  /// Get count of nodes with empty plates
  int get emptyPlateCount => _nodes.values.where(
    (n) => n.plateStatus == PlateStatus.empty
  ).length;
  
  /// Get count of cats present
  int get catsPresent => _nodes.values.where((n) => n.catPresent).length;
  
  /// Get average battery level
  double get averageBattery {
    final online = _nodes.values.where((n) => n.isOnline).toList();
    if (online.isEmpty) return 0;
    return online.fold(0.0, (sum, n) => sum + n.batteryPercent) / online.length;
  }
  
  /// Calibrate node color detection
  /// Sends calibration data to Firebase which triggers gateway to forward to MQTT
  Future<void> calibrateNodeColor(String nodeId, ColorCalibration calibration) async {
    try {
      debugPrint('📡 Calibrating node $nodeId with ${calibration.colorName}');
      
      // Write calibration to Firebase at: shelter/nodes/{nodeId}/calibration
      // Gateway will listen to this and forward to MQTT: shelter/node/{nodeId}/config/calibration
      await FirebaseFirestore.instance
          .collection('shelter')
          .doc('nodes')
          .collection(nodeId)
          .doc('calibration')
          .set({
            ...calibration.toJson(),
            'timestamp': FieldValue.serverTimestamp(),
          });
      
      debugPrint('✅ Calibration saved to Firebase for node $nodeId');
    } catch (e) {
      debugPrint('❌ Failed to calibrate node $nodeId: $e');
      rethrow;
    }
  }
  
  /// Refresh data
  Future<void> refreshData() async {
    await _loadData();
  }
  
  /// Clean up
  @override
  void dispose() {
    for (final sub in _nodeListeners.values) {
      sub.cancel();
    }
    _alertsListener?.cancel();
    _routingListener?.cancel();
    super.dispose();
  }
}
