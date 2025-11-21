enum FeedingType {
  manual,
  scheduled,
}

class FeedingLog {
  final String id;
  final DateTime timestamp;
  final double amount; // in grams
  final FeedingType type;
  final bool success;
  
  FeedingLog({
    required this.id,
    required this.timestamp,
    required this.amount,
    required this.type,
    required this.success,
  });
  
  // Convert to Map for Firebase (Phase 2)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'amount': amount,
      'type': type.toString(),
      'success': success,
    };
  }
  
  // Create from Map (Phase 2)
  factory FeedingLog.fromMap(Map<String, dynamic> map) {
    return FeedingLog(
      id: map['id'],
      timestamp: DateTime.parse(map['timestamp']),
      amount: map['amount'],
      type: map['type'] == 'FeedingType.manual' 
          ? FeedingType.manual 
          : FeedingType.scheduled,
      success: map['success'],
    );
  }
}

