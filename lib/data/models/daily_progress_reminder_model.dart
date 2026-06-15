import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class DailyProgressReminderPreference {
  const DailyProgressReminderPreference({
    this.enabled = false,
    this.hour = 22,
    this.minute = 0,
    this.updatedAt,
  });

  final bool enabled;
  final int hour;
  final int minute;
  final String? updatedAt;

  static const defaults = DailyProgressReminderPreference();

  factory DailyProgressReminderPreference.fromJson(Map<String, dynamic> json) {
    final time = json['reminderTime'] as String?;
    final parsed = time != null ? _parseTime(time) : null;
    return DailyProgressReminderPreference(
      enabled: json['enabled'] as bool? ??
          json['dailyProgressReminderEnabled'] as bool? ??
          false,
      hour: (json['hour'] as num?)?.toInt() ??
          parsed?.hour ??
          (json['reminderHour'] as num?)?.toInt() ??
          22,
      minute: (json['minute'] as num?)?.toInt() ??
          parsed?.minute ??
          (json['reminderMinute'] as num?)?.toInt() ??
          0,
      updatedAt: json['updatedAt'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'hour': hour,
        'minute': minute,
        'reminderTime': apiTime,
        'updatedAt': updatedAt ?? DateTime.now().toIso8601String(),
      };

  DailyProgressReminderPreference copyWith({
    bool? enabled,
    int? hour,
    int? minute,
  }) =>
      DailyProgressReminderPreference(
        enabled: enabled ?? this.enabled,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        updatedAt: DateTime.now().toIso8601String(),
      );

  TimeOfDay get timeOfDay => TimeOfDay(hour: hour, minute: minute);

  String get apiTime =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  String get displayTime {
    final date = DateTime(2024, 1, 1, hour, minute);
    return DateFormat('h:mm a').format(date);
  }

  static TimeOfDay? _parseTime(String value) {
    final parts = value.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }
}
