import 'package:flutter/material.dart';

/// Model for a feeding schedule.
class FeedingSchedule {
  final String id;
  final String name;
  final TimeOfDay time;
  final double amount;
  final bool isActive;
  final List<int> weekdays; // 1-7 (Monday-Sunday)
  final DateTime? createdAt;
  final DateTime? updatedAt;

  FeedingSchedule({
    required this.id,
    required this.name,
    required this.time,
    required this.amount,
    required this.isActive,
    required this.weekdays,
    this.createdAt,
    this.updatedAt,
  });

  /// Create a copy with updated fields
  FeedingSchedule copyWith({
    String? id,
    String? name,
    TimeOfDay? time,
    double? amount,
    bool? isActive,
    List<int>? weekdays,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FeedingSchedule(
      id: id ?? this.id,
      name: name ?? this.name,
      time: time ?? this.time,
      amount: amount ?? this.amount,
      isActive: isActive ?? this.isActive,
      weekdays: weekdays ?? this.weekdays,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Convert to Map for Firestore/JSON
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'timeHour': time.hour,
      'timeMinute': time.minute,
      'amount': amount,
      'isActive': isActive,
      'weekdays': weekdays,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  /// Create from Map (Firestore/JSON)
  factory FeedingSchedule.fromMap(Map<String, dynamic> map) {
    // Safely parse weekdays list from Firestore (comes as List<dynamic>)
    List<int> parsedWeekdays;
    final weekdaysData = map['weekdays'];
    if (weekdaysData is List) {
      parsedWeekdays = weekdaysData.map((e) => (e as num).toInt()).toList();
    } else {
      parsedWeekdays = [1, 2, 3, 4, 5, 6, 7];
    }
    
    // Safely parse dates
    DateTime? parsedCreatedAt;
    DateTime? parsedUpdatedAt;
    try {
      if (map['createdAt'] != null) {
        parsedCreatedAt = DateTime.parse(map['createdAt'].toString());
      }
      if (map['updatedAt'] != null) {
        parsedUpdatedAt = DateTime.parse(map['updatedAt'].toString());
      }
    } catch (_) {
      // Ignore date parsing errors
    }
    
    return FeedingSchedule(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      time: TimeOfDay(
        hour: (map['timeHour'] as num?)?.toInt() ?? 0,
        minute: (map['timeMinute'] as num?)?.toInt() ?? 0,
      ),
      amount: (map['amount'] as num?)?.toDouble() ?? 50.0,
      isActive: map['isActive'] as bool? ?? true,
      weekdays: parsedWeekdays,
      createdAt: parsedCreatedAt,
      updatedAt: parsedUpdatedAt,
    );
  }

  /// Get formatted time string
  String get formattedTime {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  /// Get weekdays as formatted string
  String get formattedWeekdays {
    if (weekdays.length == 7) {
      return 'Every day';
    }
    
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final sortedDays = List<int>.from(weekdays)..sort();
    return sortedDays.map((day) => days[day - 1]).join(', ');
  }

  /// Check if schedule is active today
  bool get isActiveToday {
    if (!isActive) return false;
    final today = DateTime.now().weekday; // 1 = Monday, 7 = Sunday
    return weekdays.contains(today);
  }
}

