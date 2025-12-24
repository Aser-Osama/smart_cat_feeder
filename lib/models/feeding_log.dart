import 'package:cloud_firestore/cloud_firestore.dart';

enum FeedingType {
  manual,
  scheduled,
}

/// Model for a feeding event log entry.
class FeedingLog {
  final String id;
  final DateTime timestamp;
  final double amount; // in grams
  final FeedingType type;
  final bool success;
  final String? scheduleName; // Name of schedule if type is scheduled
  final String? scheduleId; // ID of schedule if type is scheduled
  final String? notes; // Optional notes
  final String? source; // 'manual', 'scheduled', 'iot' - where the feed originated

  FeedingLog({
    required this.id,
    required this.timestamp,
    required this.amount,
    required this.type,
    required this.success,
    this.scheduleName,
    this.scheduleId,
    this.notes,
    this.source,
  });

  /// Create a copy with updated fields
  FeedingLog copyWith({
    String? id,
    DateTime? timestamp,
    double? amount,
    FeedingType? type,
    bool? success,
    String? scheduleName,
    String? scheduleId,
    String? notes,
    String? source,
  }) {
    return FeedingLog(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      success: success ?? this.success,
      scheduleName: scheduleName ?? this.scheduleName,
      scheduleId: scheduleId ?? this.scheduleId,
      notes: notes ?? this.notes,
      source: source ?? this.source,
    );
  }

  /// Convert to Map for Firestore/JSON
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'amount': amount,
      'type': type == FeedingType.manual ? 'manual' : 'scheduled',
      'success': success,
      'scheduleName': scheduleName,
      'scheduleId': scheduleId,
      'notes': notes,
      'source': source,
    };
  }

  /// Convert to Firestore document data
  Map<String, dynamic> toFirestore() {
    return {
      'timestamp': Timestamp.fromDate(timestamp),
      'amount': amount,
      'type': type == FeedingType.manual ? 'manual' : 'scheduled',
      'success': success,
      'scheduleName': scheduleName,
      'scheduleId': scheduleId,
      'notes': notes,
      'source': source,
    };
  }

  /// Create from Map (JSON)
  factory FeedingLog.fromMap(Map<String, dynamic> map) {
    return FeedingLog(
      id: map['id'] ?? '',
      timestamp: map['timestamp'] is String 
          ? DateTime.parse(map['timestamp'])
          : (map['timestamp'] as Timestamp).toDate(),
      amount: (map['amount'] ?? 0.0).toDouble(),
      type: map['type'] == 'manual' ? FeedingType.manual : FeedingType.scheduled,
      success: map['success'] ?? true,
      scheduleName: map['scheduleName'],
      scheduleId: map['scheduleId'],
      notes: map['notes'],
      source: map['source'],
    );
  }

  /// Create from Firestore document
  factory FeedingLog.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    // Safely parse timestamp
    DateTime parsedTimestamp;
    final timestampData = data['timestamp'];
    if (timestampData is Timestamp) {
      parsedTimestamp = timestampData.toDate();
    } else if (timestampData is String) {
      parsedTimestamp = DateTime.tryParse(timestampData) ?? DateTime.now();
    } else {
      parsedTimestamp = DateTime.now();
    }
    
    return FeedingLog(
      id: doc.id,
      timestamp: parsedTimestamp,
      amount: (data['amount'] ?? 0.0).toDouble(),
      type: data['type'] == 'manual' ? FeedingType.manual : FeedingType.scheduled,
      success: data['success'] ?? true,
      scheduleName: data['scheduleName'],
      scheduleId: data['scheduleId'],
      notes: data['notes'],
      source: data['source'],
    );
  }

  /// Check if this log is from today
  bool get isToday {
    final now = DateTime.now();
    return timestamp.year == now.year &&
        timestamp.month == now.month &&
        timestamp.day == now.day;
  }

  /// Check if this log is from this week
  bool get isThisWeek {
    final now = DateTime.now();
    final difference = now.difference(timestamp).inDays;
    return difference < 7;
  }

  /// Get type as display string
  String get typeDisplayName {
    return type == FeedingType.manual ? 'Manual Feeding' : 'Scheduled Feeding';
  }
}
