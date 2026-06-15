import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/local/local_store.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/sync/local_tables.dart';
import '../../core/sync/offline_queue_service.dart';
import '../models/daily_progress_reminder_model.dart';

class DailyProgressReminderRepository {
  DailyProgressReminderRepository({
    required LocalStore store,
    required OfflineQueueService offlineQueue,
    required ApiClient client,
  })  : _store = store,
        _offlineQueue = offlineQueue,
        _client = client;

  final LocalStore _store;
  final OfflineQueueService _offlineQueue;
  final ApiClient _client;

  DailyProgressReminderPreference getPreference() {
    final cached = _store.getJson(LocalStore.dailyProgressReminderKey);
    if (cached == null) {
      final profile = _store.getJson(LocalStore.userProfileKey);
      if (profile != null &&
          (profile.containsKey('dailyProgressReminderEnabled') ||
              profile.containsKey('dailyProgressReminderTime'))) {
        return DailyProgressReminderPreference.fromJson({
          'enabled': false,
          'reminderTime':
              profile['dailyProgressReminderTime'] as String? ?? '22:00',
        });
      }
      return DailyProgressReminderPreference.defaults;
    }
    if (cached.isEmpty) return DailyProgressReminderPreference.defaults;
    return DailyProgressReminderPreference.fromJson(cached);
  }

  Future<void> savePreference(
    DailyProgressReminderPreference preference,
  ) async {
    final json = preference.toJson();
    await _store.putJson(LocalStore.dailyProgressReminderKey, json);
    await _offlineQueue.enqueue(
      entityType: 'REMINDER_PREFERENCE',
      entityId: 'daily-progress-reminder',
      action: 'DAILY_PROGRESS_REMINDER',
      payload: json,
    );
  }

  Future<void> refreshPreferenceFromBackend() async {
    try {
      final response = await _client.dio.get(ApiEndpoints.reminderPreference);
      final data = response.data['data'];
      if (data is Map<String, dynamic>) {
        final remote = DailyProgressReminderPreference.fromJson(data);
        final current = getPreference();
        await _store.putJson(
          LocalStore.dailyProgressReminderKey,
          remote.copyWith(enabled: current.enabled).toJson(),
        );
      }
    } on DioException {
      // Offline is expected; local settings remain authoritative until sync.
    }
  }

  bool shouldShowReminderIntro() {
    if (kIsWeb) return false;
    if (_store.getString(LocalStore.dailyProgressReminderPromptPendingKey) !=
        'true') {
      return false;
    }
    if (_store.hasSeenDailyProgressReminderIntro()) return false;
    if (getPreference().enabled) return false;
    return true;
  }

  Future<void> markFirstTopicCompletedPromptPending() async {
    if (kIsWeb) return;
    if (_store.hasSeenDailyProgressReminderIntro()) return;
    if (getPreference().enabled) return;
    await _store.putString(
      LocalStore.dailyProgressReminderPromptPendingKey,
      'true',
    );
  }

  Future<void> markReminderIntroShown() async {
    await _store.markDailyProgressReminderIntroShown();
    await _store.deleteKey(LocalStore.dailyProgressReminderPromptPendingKey);
  }

  Future<void> flushQueuedPreference(Map<String, dynamic> item) async {
    final payload = item['payload'];
    if (payload is! Map<String, dynamic>) {
      await _offlineQueue.removeByClientId(item['clientId'] as String);
      return;
    }
    await _client.dio.put(ApiEndpoints.reminderPreference, data: payload);
    await _offlineQueue.removeByClientId(item['clientId'] as String);
  }

  Future<void> markNoStudyDay({DateTime? date}) async {
    final day = _dateKey(date ?? DateTime.now());
    final noStudyDays = Map<String, dynamic>.from(
      _store.getJson(LocalStore.dailyNoStudyDaysKey) ?? {},
    );
    noStudyDays[day] = {
      'studyDate': day,
      'noStudyDay': true,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    await _store.putJson(LocalStore.dailyNoStudyDaysKey, noStudyDays);
    await _writeNoStudyDailyLog(day, LocalTables.syncStatusPending);
    await _offlineQueue.enqueue(
      entityType: 'NO_STUDY_DAY',
      entityId: day,
      action: 'NO_STUDY_DAY',
      payload: {
        'studyDate': day,
        'noStudyDay': true,
        'createdAt': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<void> flushQueuedNoStudyDay(Map<String, dynamic> item) async {
    final payload = item['payload'];
    if (payload is! Map<String, dynamic>) {
      await _offlineQueue.removeByClientId(item['clientId'] as String);
      return;
    }
    final studyDate = payload['studyDate'] as String?;
    if (studyDate == null) {
      await _offlineQueue.removeByClientId(item['clientId'] as String);
      return;
    }
    await _client.dio.post(ApiEndpoints.noStudyDay, data: payload);
    await _writeNoStudyDailyLog(studyDate, LocalTables.syncStatusSynced);
    await _offlineQueue.removeByClientId(item['clientId'] as String);
  }

  bool wasNoStudySelected({DateTime? date}) {
    final day = _dateKey(date ?? DateTime.now());
    final days = _store.getJson(LocalStore.dailyNoStudyDaysKey);
    final row = days?[day];
    if (row is Map<String, dynamic> && row['noStudyDay'] == true) return true;

    final logs = _store.getJson(LocalTables.dailyStudyLogs);
    final log = logs?[day];
    return log is Map<String, dynamic> && log['noStudyDay'] == true;
  }

  bool hasProgressForDay({DateTime? date}) {
    final day = _dateKey(date ?? DateTime.now());
    final logs = _store.getJson(LocalTables.dailyStudyLogs);
    final log = logs?[day];
    if (log is! Map<String, dynamic>) return false;
    final hours = ((log['hoursStudied'] as num?) ?? 0).toDouble();
    final topics = ((log['topicsCompleted'] as num?) ?? 0).toInt();
    return hours > 0 || topics > 0;
  }

  bool shouldRemindToday({DateTime? now}) {
    final date = now ?? DateTime.now();
    final pref = getPreference();
    if (!pref.enabled) return false;
    if (wasNoStudySelected(date: date)) return false;
    return !hasProgressForDay(date: date);
  }

  String todayKey() => _dateKey(DateTime.now());

  String _dateKey(DateTime date) {
    final local = date.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  Future<void> _writeNoStudyDailyLog(
      String studyDate, String syncStatus) async {
    final table = Map<String, dynamic>.from(
      _store.getJson(LocalTables.dailyStudyLogs) ?? {},
    );
    final existing = table[studyDate];
    final prev = existing is Map<String, dynamic>
        ? Map<String, dynamic>.from(existing)
        : <String, dynamic>{};
    table[studyDate] = {
      'studyDate': studyDate,
      'hoursStudied': ((prev['hoursStudied'] as num?) ?? 0).toDouble(),
      'topicsCompleted': ((prev['topicsCompleted'] as num?) ?? 0).toInt(),
      'noStudyDay': true,
      'syncStatus': syncStatus,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    await _store.putJson(LocalTables.dailyStudyLogs, table);
  }

  @visibleForTesting
  String dateKeyFor(DateTime date) => _dateKey(date);
}
