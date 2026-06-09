import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

/// Hive-backed local cache for offline-first reads.
class LocalStore {
  static const String _boxName = 'examsaathi_cache';
  static const String dashboardKey = 'dashboard';
  static const String myExamsKey = 'my_exams';
  static const String catalogKey = 'exam_catalog';
  static const String syncCatalogMasterKey = 'sync_catalog_master';
  static const String syncCatalogAtKey = 'sync_catalog_at';
  static const String syncBundleAtKey = 'sync_bundle_at';
  static const String lastSyncTimeKey = 'last_sync_time';
  static const String offlineQueueKey = 'offline_queue';
  static const String mockPerformanceKey = 'mock_performance';
  static const String userProfileKey = 'user_profile';
  static const String syncStatusKey = 'sync_status';
  static const String initialDownloadCompleteKey = 'initial_download_complete';
  static const String cachedUserIdKey = 'cached_user_id';

  Box<String>? _box;

  Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox<String>(_boxName);
  }

  Future<void> clearAll() async {
    await _box?.clear();
  }

  Future<void> putJson(String key, Object value) async {
    await _box?.put(key, jsonEncode(value));
  }

  Map<String, dynamic>? getJson(String key) {
    final raw = _box?.get(key);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  List<dynamic>? getJsonList(String key) {
    final raw = _box?.get(key);
    if (raw == null) return null;
    return jsonDecode(raw) as List<dynamic>;
  }

  String? getString(String key) => _box?.get(key);

  Future<void> putString(String key, String value) async {
    await _box?.put(key, value);
  }

  Future<void> deleteKey(String key) async {
    await _box?.delete(key);
  }

  /// Removes cached mock-test info and question banks (e.g. after server purge).
  Future<void> clearMockTestCache() async {
    final box = _box;
    if (box == null) return;
    final keys = box.keys.map((k) => k.toString()).toList();
    for (final key in keys) {
      if (key.startsWith('topic_mock_info_') ||
          key.startsWith('mock_test_questions_') ||
          key == mockPerformanceKey) {
        await deleteKey(key);
      }
    }
  }

  String subjectProgressKey(int examId) => 'subject_progress_$examId';
  String visibleSubjectsKey(int examId) => 'visible_subjects_$examId';

  /// Per-enrollment subject detail (progress differs per userExam even when subjectId is shared).
  String subjectDetailKey(int userExamId, int subjectId) =>
      'subject_detail_${userExamId}_$subjectId';

  /// Composite key for exam-scoped topic progress rows.
  static String topicProgressRowKey(int userExamId, int topicId) =>
      '$userExamId:$topicId';
  String topicMockInfoKey(int topicId) => 'topic_mock_info_$topicId';
  String mockTestQuestionsKey(int topicId) => 'mock_test_questions_$topicId';
  String mockTestLocalResultKey(String clientId) => 'mock_test_result_$clientId';

  bool isInitialDownloadComplete() =>
      getString(initialDownloadCompleteKey) == 'true';

  Future<void> markInitialDownloadComplete() async {
    await putString(initialDownloadCompleteKey, 'true');
  }

  Future<void> resetInitialDownloadComplete() async {
    await deleteKey(initialDownloadCompleteKey);
  }

  /// Last successful sync timestamp — used for incremental bundle/catalog pulls.
  DateTime? getLastSyncTime() {
    final raw = getString(lastSyncTimeKey) ?? getString(syncBundleAtKey);
    return raw != null ? DateTime.tryParse(raw) : null;
  }

  Future<void> setLastSyncTime(DateTime time) async {
    final iso = time.toIso8601String();
    await putString(lastSyncTimeKey, iso);
    await putString(syncBundleAtKey, iso);
    await putString(syncCatalogAtKey, iso);
  }

  Future<void> clearLastSyncTime() async {
    await deleteKey(lastSyncTimeKey);
    await deleteKey(syncBundleAtKey);
    await deleteKey(syncCatalogAtKey);
  }

  /// Clears user-specific study data (used when a different account logs in).
  /// Shared syllabus catalog caches are preserved.
  Future<void> clearUserStudyData() async {
    final box = _box;
    if (box == null) return;
    final keys = box.keys.map((k) => k.toString()).toList();
    for (final key in keys) {
      if (key == syncCatalogMasterKey ||
          key == syncCatalogAtKey ||
          key == catalogKey) {
        continue;
      }
      await deleteKey(key);
    }
  }
}
