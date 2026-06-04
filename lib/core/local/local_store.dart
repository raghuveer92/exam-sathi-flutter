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
  static const String offlineQueueKey = 'offline_queue';
  static const String mockPerformanceKey = 'mock_performance';

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

  String subjectProgressKey(int examId) => 'subject_progress_$examId';
  String visibleSubjectsKey(int examId) => 'visible_subjects_$examId';
  String subjectDetailKey(int subjectId) => 'subject_detail_$subjectId';
  String topicMockInfoKey(int topicId) => 'topic_mock_info_$topicId';
}
