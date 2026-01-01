import 'package:cloud_firestore/cloud_firestore.dart';

/// Types of alerts in the shelter monitoring system
enum AlertType {
  emptyPlate,      // Bowl is empty and no cat present
  lowBattery,      // Node battery below threshold
  nodeOffline,     // Node hasn't reported in
  routeChange,     // Routing path changed (informational)
  catPresent;      // Cat detected at bowl (informational)

  static AlertType fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'empty_plate':
      case 'emptyplate':
        return AlertType.emptyPlate;
      case 'low_battery':
      case 'lowbattery':
        return AlertType.lowBattery;
      case 'node_offline':
      case 'nodeoffline':
        return AlertType.nodeOffline;
      case 'route_change':
      case 'routechange':
        return AlertType.routeChange;
      case 'cat_present':
      case 'catpresent':
        return AlertType.catPresent;
      default:
        return AlertType.emptyPlate;
    }
  }

  String get displayName {
    switch (this) {
      case AlertType.emptyPlate:
        return 'Empty Plate';
      case AlertType.lowBattery:
        return 'Low Battery';
      case AlertType.nodeOffline:
        return 'Node Offline';
      case AlertType.routeChange:
        return 'Route Change';
      case AlertType.catPresent:
        return 'Cat Present';
    }
  }

  String get icon {
    switch (this) {
      case AlertType.emptyPlate:
        return '🍽️';
      case AlertType.lowBattery:
        return '🔋';
      case AlertType.nodeOffline:
        return '📡';
      case AlertType.routeChange:
        return '🔀';
      case AlertType.catPresent:
        return '🐱';
    }
  }
}

/// Severity level for alerts
enum AlertSeverity {
  info,      // Informational (cat present, route change)
  warning,   // Needs attention soon (low battery, empty plate)
  critical;  // Immediate attention (node offline, critical battery)

  static AlertSeverity fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'info':
        return AlertSeverity.info;
      case 'warning':
        return AlertSeverity.warning;
      case 'critical':
        return AlertSeverity.critical;
      default:
        return AlertSeverity.warning;
    }
  }
}

/// Represents an alert from the shelter monitoring system
class ShelterAlert {
  final String id;
  final String nodeId;
  final AlertType type;
  final AlertSeverity severity;
  final DateTime timestamp;
  final String? message;
  final Map<String, dynamic>? details;
  final bool acknowledged;
  final DateTime? acknowledgedAt;

  ShelterAlert({
    required this.id,
    required this.nodeId,
    required this.type,
    this.severity = AlertSeverity.warning,
    required this.timestamp,
    this.message,
    this.details,
    this.acknowledged = false,
    this.acknowledgedAt,
  });

  /// Create a copy with updated fields
  ShelterAlert copyWith({
    String? id,
    String? nodeId,
    AlertType? type,
    AlertSeverity? severity,
    DateTime? timestamp,
    String? message,
    Map<String, dynamic>? details,
    bool? acknowledged,
    DateTime? acknowledgedAt,
  }) {
    return ShelterAlert(
      id: id ?? this.id,
      nodeId: nodeId ?? this.nodeId,
      type: type ?? this.type,
      severity: severity ?? this.severity,
      timestamp: timestamp ?? this.timestamp,
      message: message ?? this.message,
      details: details ?? this.details,
      acknowledged: acknowledged ?? this.acknowledged,
      acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
    );
  }

  /// Get a human-readable title for this alert
  String get title {
    switch (type) {
      case AlertType.emptyPlate:
        return 'Empty Plate at Bowl $nodeId';
      case AlertType.lowBattery:
        final percent = details?['batteryPercent']?.toStringAsFixed(0) ?? '?';
        return 'Low Battery on Node $nodeId ($percent%)';
      case AlertType.nodeOffline:
        return 'Node $nodeId is Offline';
      case AlertType.routeChange:
        return 'Route Changed for Node $nodeId';
      case AlertType.catPresent:
        return 'Cat at Bowl $nodeId';
    }
  }

  /// Get the default message for this alert type
  String get defaultMessage {
    switch (type) {
      case AlertType.emptyPlate:
        return 'The food bowl at station $nodeId appears to be empty. Please refill.';
      case AlertType.lowBattery:
        final percent = details?['batteryPercent']?.toStringAsFixed(0) ?? '?';
        return 'Node $nodeId battery is at $percent%. Consider replacing soon.';
      case AlertType.nodeOffline:
        return 'Node $nodeId has not reported in recently. Check connectivity.';
      case AlertType.routeChange:
        final newRoute = details?['newRoute'] ?? 'direct';
        return 'Node $nodeId routing changed to: $newRoute';
      case AlertType.catPresent:
        return 'A cat has been detected at bowl $nodeId.';
    }
  }

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'nodeId': nodeId,
      'type': type.name,
      'severity': severity.name,
      'timestamp': Timestamp.fromDate(timestamp),
      'message': message ?? defaultMessage,
      'details': details,
      'acknowledged': acknowledged,
      'acknowledgedAt': acknowledgedAt != null 
          ? Timestamp.fromDate(acknowledgedAt!) 
          : null,
    };
  }

  /// Create from Firestore document
  factory ShelterAlert.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return ShelterAlert.fromMap(data, doc.id);
  }

  /// Create from Map with id override
  factory ShelterAlert.fromMap(Map<String, dynamic> data, [String? idOverride]) {
    // Parse timestamp
    DateTime timestamp;
    if (data['timestamp'] is Timestamp) {
      timestamp = (data['timestamp'] as Timestamp).toDate();
    } else if (data['timestamp'] is int) {
      timestamp = DateTime.fromMillisecondsSinceEpoch(data['timestamp']);
    } else {
      timestamp = DateTime.now();
    }

    // Parse acknowledgedAt
    DateTime? acknowledgedAt;
    if (data['acknowledgedAt'] != null) {
      if (data['acknowledgedAt'] is Timestamp) {
        acknowledgedAt = (data['acknowledgedAt'] as Timestamp).toDate();
      } else if (data['acknowledgedAt'] is int) {
        acknowledgedAt = DateTime.fromMillisecondsSinceEpoch(data['acknowledgedAt']);
      }
    }

    return ShelterAlert(
      id: idOverride ?? data['id'] ?? '',
      nodeId: data['nodeId'] ?? '',
      type: AlertType.fromString(data['type']),
      severity: AlertSeverity.fromString(data['severity']),
      timestamp: timestamp,
      message: data['message'],
      details: data['details'] != null 
          ? Map<String, dynamic>.from(data['details']) 
          : null,
      acknowledged: data['acknowledged'] ?? false,
      acknowledgedAt: acknowledgedAt,
    );
  }

  /// Check if alert is recent (within last hour)
  bool get isRecent {
    return DateTime.now().difference(timestamp).inHours < 1;
  }

  /// Check if alert needs attention (unacknowledged warning/critical)
  bool get needsAttention {
    return !acknowledged && 
           (severity == AlertSeverity.warning || 
            severity == AlertSeverity.critical);
  }

  @override
  String toString() {
    return 'ShelterAlert($nodeId: ${type.displayName}, $severity, ack=$acknowledged)';
  }
}

/// Alert statistics for the dashboard
class AlertStats {
  final int totalAlerts;
  final int unacknowledged;
  final int emptyPlates;
  final int lowBatteryNodes;
  final int offlineNodes;

  AlertStats({
    required this.totalAlerts,
    required this.unacknowledged,
    required this.emptyPlates,
    required this.lowBatteryNodes,
    required this.offlineNodes,
  });

  factory AlertStats.empty() {
    return AlertStats(
      totalAlerts: 0,
      unacknowledged: 0,
      emptyPlates: 0,
      lowBatteryNodes: 0,
      offlineNodes: 0,
    );
  }

  factory AlertStats.fromAlerts(List<ShelterAlert> alerts) {
    return AlertStats(
      totalAlerts: alerts.length,
      unacknowledged: alerts.where((a) => !a.acknowledged).length,
      emptyPlates: alerts
          .where((a) => a.type == AlertType.emptyPlate && !a.acknowledged)
          .length,
      lowBatteryNodes: alerts
          .where((a) => a.type == AlertType.lowBattery && !a.acknowledged)
          .length,
      offlineNodes: alerts
          .where((a) => a.type == AlertType.nodeOffline && !a.acknowledged)
          .length,
    );
  }

  bool get hasIssues => unacknowledged > 0;
}
