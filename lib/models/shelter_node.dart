import 'package:cloud_firestore/cloud_firestore.dart';
import 'color_calibration.dart';

/// Represents one of the 4 shelter monitoring nodes (W, X, Y, Z).
/// Each node monitors a single bowl/feeding station.
class ShelterNode {
  final String nodeId; // W, X, Y, Z
  final String displayName; // "Bowl W", "Station X", etc.
  final PlateStatus plateStatus;
  final bool catPresent;
  final double batteryPercent;
  final double? batteryVoltage;
  final int? rssi;
  final int hopCount;
  final List<String> route;
  final String? nextHop;
  final DateTime? lastUpdate;
  final bool isOnline;
  final ColorReading? lastColorReading;
  final double? ultrasonicDistanceCm;
  final ColorCalibration? currentCalibration;

  ShelterNode({
    required this.nodeId,
    String? displayName,
    this.plateStatus = PlateStatus.unknown,
    this.catPresent = false,
    this.batteryPercent = 100.0,
    this.batteryVoltage,
    this.rssi,
    this.hopCount = 0,
    this.route = const [],
    this.nextHop,
    this.lastUpdate,
    this.isOnline = false,
    this.lastColorReading,
    this.ultrasonicDistanceCm,
    this.currentCalibration,
  }) : displayName = displayName ?? 'Bowl $nodeId';

  /// Create a copy with updated fields
  ShelterNode copyWith({
    String? nodeId,
    String? displayName,
    PlateStatus? plateStatus,
    bool? catPresent,
    double? batteryPercent,
    double? batteryVoltage,
    int? rssi,
    int? hopCount,
    List<String>? route,
    String? nextHop,
    DateTime? lastUpdate,
    bool? isOnline,
    ColorReading? lastColorReading,
    double? ultrasonicDistanceCm,
    ColorCalibration? currentCalibration,
  }) {
    return ShelterNode(
      nodeId: nodeId ?? this.nodeId,
      displayName: displayName ?? this.displayName,
      plateStatus: plateStatus ?? this.plateStatus,
      catPresent: catPresent ?? this.catPresent,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      batteryVoltage: batteryVoltage ?? this.batteryVoltage,
      rssi: rssi ?? this.rssi,
      hopCount: hopCount ?? this.hopCount,
      route: route ?? this.route,
      nextHop: nextHop ?? this.nextHop,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      isOnline: isOnline ?? this.isOnline,
      lastColorReading: lastColorReading ?? this.lastColorReading,
      ultrasonicDistanceCm: ultrasonicDistanceCm ?? this.ultrasonicDistanceCm,
      currentCalibration: currentCalibration ?? this.currentCalibration,
    );
  }

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'nodeId': nodeId,
      'displayName': displayName,
      'plateStatus': plateStatus.name,
      'catPresent': catPresent,
      'batteryPercent': batteryPercent,
      'batteryVoltage': batteryVoltage,
      'rssi': rssi,
      'hopCount': hopCount,
      'route': route,
      'nextHop': nextHop,
      'lastUpdate': lastUpdate != null ? Timestamp.fromDate(lastUpdate!) : null,
      'isOnline': isOnline,
      'lastColorReading': lastColorReading?.toMap(),
      'ultrasonicDistanceCm': ultrasonicDistanceCm,
    };
  }

  /// Create from Firestore document
  factory ShelterNode.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return ShelterNode.fromMap(data, doc.id);
  }

  /// Create from Map with nodeId override
  factory ShelterNode.fromMap(Map<String, dynamic> data, [String? nodeIdOverride]) {
    // Parse lastUpdate
    DateTime? lastUpdate;
    if (data['lastUpdate'] != null) {
      if (data['lastUpdate'] is Timestamp) {
        lastUpdate = (data['lastUpdate'] as Timestamp).toDate();
      } else if (data['lastUpdate'] is int) {
        lastUpdate = DateTime.fromMillisecondsSinceEpoch(data['lastUpdate']);
      }
    }

    // Parse route
    List<String> route = [];
    if (data['route'] != null) {
      route = List<String>.from(data['route']);
    }

    // Parse color reading
    ColorReading? colorReading;
    if (data['lastColorReading'] != null) {
      colorReading = ColorReading.fromMap(data['lastColorReading']);
    }

    return ShelterNode(
      nodeId: nodeIdOverride ?? data['nodeId'] ?? 'X',
      displayName: data['displayName'],
      plateStatus: PlateStatus.fromString(data['plateStatus']),
      catPresent: data['catPresent'] ?? false,
      batteryPercent: (data['batteryPercent'] ?? 100.0).toDouble(),
      batteryVoltage: data['batteryVoltage']?.toDouble(),
      rssi: data['rssi'],
      hopCount: data['hopCount'] ?? 0,
      route: route,
      nextHop: data['nextHop'],
      lastUpdate: lastUpdate,
      isOnline: data['isOnline'] ?? false,
      lastColorReading: colorReading,
      ultrasonicDistanceCm: data['ultrasonicDistanceCm']?.toDouble(),
    );
  }

  /// Check if node data is stale (no update in 2 minutes)
  bool get isStale {
    if (lastUpdate == null) return true;
    return DateTime.now().difference(lastUpdate!).inMinutes > 2;
  }

  /// Get battery status category
  BatteryStatus get batteryStatus {
    if (batteryPercent > 60) return BatteryStatus.good;
    if (batteryPercent > 30) return BatteryStatus.medium;
    if (batteryPercent > 10) return BatteryStatus.low;
    return BatteryStatus.critical;
  }

  /// Get signal strength category
  SignalStrength get signalStrength {
    if (rssi == null) return SignalStrength.unknown;
    if (rssi! > -50) return SignalStrength.excellent;
    if (rssi! > -65) return SignalStrength.good;
    if (rssi! > -80) return SignalStrength.fair;
    return SignalStrength.poor;
  }

  @override
  String toString() {
    return 'ShelterNode($nodeId: plate=$plateStatus, cat=$catPresent, battery=${batteryPercent.toStringAsFixed(1)}%)';
  }
}

/// Plate status for a bowl
enum PlateStatus {
  filled,    // Brown food detected
  empty,     // No brown food detected
  unknown;   // No reading yet

  static PlateStatus fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'filled':
        return PlateStatus.filled;
      case 'empty':
        return PlateStatus.empty;
      default:
        return PlateStatus.unknown;
    }
  }

  String get displayName {
    switch (this) {
      case PlateStatus.filled:
        return 'Filled';
      case PlateStatus.empty:
        return 'Empty';
      case PlateStatus.unknown:
        return 'Unknown';
    }
  }
}

/// Battery status categories
enum BatteryStatus {
  good,     // > 60%
  medium,   // 30-60%
  low,      // 10-30%
  critical; // < 10%
}

/// WiFi signal strength categories
enum SignalStrength {
  excellent, // > -50 dBm
  good,      // -50 to -65 dBm
  fair,      // -65 to -80 dBm
  poor,      // < -80 dBm
  unknown;
}

/// Color sensor reading from TCS3200
/// Full RGB values for brown food detection
class ColorReading {
  final int red;      // Red channel pulse count
  final int green;    // Green channel pulse count
  final int blue;     // Blue channel pulse count
  final bool isBrown; // True if brown food detected

  ColorReading({
    required this.red,
    required this.green,
    required this.blue,
    required this.isBrown,
  });

  /// Thresholds matching ESP8266 config.h (20% frequency, real calibration)
  static const int brownRedMin = 200;
  static const int brownRedMax = 1200;
  static const int brownGreenMin = 150;
  static const int brownGreenMax = 1000;
  static const int brownBlueMin = 100;
  static const int brownBlueMax = 950;
  static const int darkThreshold = 150;
  static const double greenRedRatioMin = 0.65;
  static const double greenRedRatioMax = 1.0;

  /// Returns the food detection type for UI
  FoodDetectionType get foodType {
    // Check if too dark (empty)
    if (red < darkThreshold || green < darkThreshold) {
      return FoodDetectionType.empty;
    }
    
    // Check if blue exceeds red or green (not brown - blue tint)
    if (blue > green || blue > red) {
      return FoodDetectionType.other;
    }
    
    // Check if values are in brown range
    if (red >= brownRedMin && red <= brownRedMax &&
        green >= brownGreenMin && green <= brownGreenMax &&
        blue >= brownBlueMin && blue <= brownBlueMax) {
      // Check green/red ratio
      if (red > 0) {
        double grRatio = green / red;
        if (grRatio >= greenRedRatioMin && grRatio <= greenRedRatioMax) {
          return FoodDetectionType.brown;
        }
      }
    }
    
    // Not brown - could be other food or non-food
    return FoodDetectionType.other;
  }

  Map<String, dynamic> toMap() {
    return {
      'red': red,
      'green': green,
      'blue': blue,
      'isBrown': isBrown,
    };
  }

  factory ColorReading.fromMap(Map<String, dynamic> data) {
    return ColorReading(
      red: data['red'] ?? 0,
      green: data['green'] ?? 0,
      blue: data['blue'] ?? 0,
      isBrown: data['isBrown'] ?? false,
    );
  }

  @override
  String toString() {
    return 'Pulses($red) foodType=$foodType isBrown=$isBrown';
  }
}

/// Food detection type for UI
enum FoodDetectionType {
  empty,  // Dark surface - no food
  brown,  // Brown food detected (correct)
  other,  // Other color - not brown food
}

/// Routing candidate for multi-hop decisions
class RoutingCandidate {
  final String targetNodeId;
  final int rssi;
  final double batteryPercent;
  final double score;

  RoutingCandidate({
    required this.targetNodeId,
    required this.rssi,
    required this.batteryPercent,
    required this.score,
  });

  factory RoutingCandidate.fromMap(Map<String, dynamic> data) {
    return RoutingCandidate(
      targetNodeId: data['target'] ?? '',
      rssi: data['rssi'] ?? -100,
      batteryPercent: (data['battery'] ?? 0).toDouble(),
      score: (data['score'] ?? 0).toDouble(),
    );
  }
}

/// Routing decision log entry
class RoutingDecision {
  final String nodeId;
  final DateTime timestamp;
  final String? previousNextHop;
  final String newNextHop;
  final String reason;
  final List<RoutingCandidate> candidates;
  final double selectedScore;

  RoutingDecision({
    required this.nodeId,
    required this.timestamp,
    this.previousNextHop,
    required this.newNextHop,
    required this.reason,
    required this.candidates,
    required this.selectedScore,
  });

  factory RoutingDecision.fromMap(Map<String, dynamic> data) {
    // Parse candidates
    List<RoutingCandidate> candidates = [];
    if (data['routingDecision']?['candidates'] != null) {
      candidates = (data['routingDecision']['candidates'] as List)
          .map((c) => RoutingCandidate.fromMap(c))
          .toList();
    }

    // Parse timestamp
    DateTime timestamp;
    if (data['timestamp'] is Timestamp) {
      timestamp = (data['timestamp'] as Timestamp).toDate();
    } else if (data['timestamp'] is int) {
      timestamp = DateTime.fromMillisecondsSinceEpoch(data['timestamp']);
    } else {
      timestamp = DateTime.now();
    }

    final decision = data['routingDecision'] ?? {};

    return RoutingDecision(
      nodeId: data['nodeId'] ?? '',
      timestamp: timestamp,
      previousNextHop: decision['previousNextHop'],
      newNextHop: decision['newNextHop'] ?? 'SINK',
      reason: decision['reason'] ?? '',
      candidates: candidates,
      selectedScore: (decision['selectedScore'] ?? 0).toDouble(),
    );
  }
}
