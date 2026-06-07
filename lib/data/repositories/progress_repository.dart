import 'dart:async';

import 'package:dio/dio.dart';

import '../models/subject_detail_model.dart';
import '../models/topic_model.dart';
import '../../core/local/api_call_tracker.dart';
import '../../core/local/local_store.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/sync/offline_queue_service.dart';

/// All reads from local cache. All writes to cache + pending sync queue.
class ProgressRepository {
  ProgressRepository({
    required ApiClient client,
    required LocalStore store,
    required OfflineQueueService offlineQueue,
  })  : _client = client,
        _store = store,
        _offlineQueue = offlineQueue;

  final ApiClient _client;
  final LocalStore _store;
  final OfflineQueueService _offlineQueue;

  Future<SubjectDetailModel?> getSubjectDetailCached(int subjectId) async {
    final data = _store.getJson(_store.subjectDetailKey(subjectId));
    if (data == null) return null;
    return SubjectDetailModel.fromJson(data);
  }

  /// Local-first read — never hits network during normal usage.
  Future<SubjectDetailModel> getSubjectDetail(
    int subjectId, {
    bool forceRemote = false,
  }) async {
    final cached = await getSubjectDetailCached(subjectId);
    if (!forceRemote) {
      if (cached != null) return cached;
      final fromCatalog = await _materializeSubjectDetailFromCatalog(subjectId);
      if (fromCatalog != null) return fromCatalog;
      throw StateError(
        'Topics not downloaded yet. Connect to internet and tap SYNC.',
      );
    }
    try {
      ApiCallTracker.instance.record('GET ${ApiEndpoints.subjectDetail(subjectId)}');
      final response = await _client.dio.get(ApiEndpoints.subjectDetail(subjectId));
      final data = response.data['data'] as Map<String, dynamic>;
      await _store.putJson(_store.subjectDetailKey(subjectId), data);
      return SubjectDetailModel.fromJson(data);
    } catch (_) {
      if (cached != null) return cached;
      final fromCatalog = await _materializeSubjectDetailFromCatalog(subjectId);
      if (fromCatalog != null) return fromCatalog;
      rethrow;
    }
  }

  /// Pre-build subject detail caches from synced catalog (chapters + topics).
  Future<void> materializeSubjectDetailsFromCatalog(Iterable<int> subjectIds) async {
    for (final subjectId in subjectIds) {
      await _materializeSubjectDetailFromCatalog(subjectId);
    }
  }

  /// Build subject detail from `/sync/catalog` when per-subject API cache is missing.
  Future<SubjectDetailModel?> _materializeSubjectDetailFromCatalog(
    int subjectId,
  ) async {
    if (_store.getJson(_store.subjectDetailKey(subjectId)) != null) {
      return getSubjectDetailCached(subjectId);
    }
    final data = _buildSubjectDetailMapFromCatalog(subjectId);
    if (data == null) return null;
    await _store.putJson(_store.subjectDetailKey(subjectId), data);
    return SubjectDetailModel.fromJson(data);
  }

  Map<String, dynamic>? _buildSubjectDetailMapFromCatalog(int subjectId) {
    final catalog = _store.getJson(LocalStore.syncCatalogMasterKey);
    if (catalog == null) return null;

    final subjects = catalog['subjects'];
    final chapters = catalog['chapters'];
    final topics = catalog['topics'];
    if (subjects is! List || chapters is! List || topics is! List) {
      return null;
    }

    Map<String, dynamic>? subjectMeta;
    for (final raw in subjects) {
      if (raw is! Map<String, dynamic>) continue;
      if ((raw['id'] as num?)?.toInt() == subjectId) {
        subjectMeta = raw;
        break;
      }
    }
    if (subjectMeta == null) return null;

    final subjectChapters = chapters
        .whereType<Map<String, dynamic>>()
        .where((c) => (c['subjectId'] as num?)?.toInt() == subjectId)
        .where((c) => c['isActive'] != false)
        .toList()
      ..sort(
        (a, b) => ((a['orderIndex'] as num?) ?? 0)
            .compareTo((b['orderIndex'] as num?) ?? 0),
      );

    final chapterMaps = <Map<String, dynamic>>[];
    var totalTopics = 0;
    var completedTopics = 0;

    for (final chapter in subjectChapters) {
      final chapterId = (chapter['id'] as num).toInt();
      final chapterTitle = chapter['title'] as String;
      final chapterTopics = topics
          .whereType<Map<String, dynamic>>()
          .where((t) => (t['chapterId'] as num?)?.toInt() == chapterId)
          .where((t) => t['isActive'] != false)
          .toList()
        ..sort(
          (a, b) => ((a['orderIndex'] as num?) ?? 0)
              .compareTo((b['orderIndex'] as num?) ?? 0),
        );

      final topicMaps = <Map<String, dynamic>>[];
      var chapterCompleted = 0;
      for (final topic in chapterTopics) {
        topicMaps.add({
          'id': (topic['id'] as num).toInt(),
          'chapterId': chapterId,
          'chapterTitle': chapterTitle,
          'title': topic['title'],
          'description': topic['description'],
          'estimatedHours': (topic['estimatedHours'] as num?) ?? 1.0,
          'difficultyLevel': topic['difficultyLevel'] ?? 'MEDIUM',
          'orderIndex': (topic['orderIndex'] as num?) ?? 0,
          'isActive': topic['isActive'] ?? true,
          'isCompleted': false,
          'actualHours': 0.0,
          'status': 'NOT_STARTED',
        });
        totalTopics++;
      }

      chapterMaps.add({
        'id': chapterId,
        'title': chapterTitle,
        'description': chapter['description'],
        'orderIndex': (chapter['orderIndex'] as num?) ?? 0,
        'totalTopics': chapterTopics.length,
        'completedTopics': chapterCompleted,
        'completionPercent':
            chapterTopics.isEmpty ? 0.0 : (chapterCompleted * 100.0 / chapterTopics.length),
        'topics': topicMaps,
      });
    }

    if (chapterMaps.isEmpty) return null;

    return {
      'subjectId': subjectId,
      'subjectName': subjectMeta['name'] as String,
      'iconName': subjectMeta['iconName'] ?? 'book',
      'colorCode': subjectMeta['colorCode'] ?? '#6C63FF',
      'totalTopics': totalTopics,
      'completedTopics': completedTopics,
      'completionPercent':
          totalTopics == 0 ? 0.0 : (completedTopics * 100.0 / totalTopics),
      'totalStudyHours': 0.0,
      'chapters': chapterMaps,
    };
  }

  /// Queue-only write — synced when user taps SYNC.
  Future<void> markTopicComplete({
    required int topicId,
    required bool isCompleted,
    double actualHours = 0.0,
  }) async {
    await _offlineQueue.enqueue(
      entityType: 'TOPIC',
      entityId: topicId.toString(),
      action: isCompleted ? 'COMPLETE_TOPIC' : 'ADD_STUDY_HOURS',
      payload: {
        'topicId': topicId,
        'isCompleted': isCompleted,
        'actualHours': actualHours,
      },
    );
  }

  /// Upload one queued topic-progress row (uses direct API — batch /sync/push 500s on prod).
  Future<void> flushQueuedTopicProgress(Map<String, dynamic> item) async {
    final payload = item['payload'];
    if (payload is! Map<String, dynamic>) {
      await _offlineQueue.removeByClientId(item['clientId'] as String);
      return;
    }
    final topicId = (payload['topicId'] as num?)?.toInt();
    if (topicId == null) {
      await _offlineQueue.removeByClientId(item['clientId'] as String);
      return;
    }

    try {
      ApiCallTracker.instance.record('POST ${ApiEndpoints.updateProgress}');
      await _client.dio.post(
        ApiEndpoints.updateProgress,
        data: {
          'topicId': topicId,
          'isCompleted': payload['isCompleted'] ?? false,
          'actualHours': (payload['actualHours'] as num?)?.toDouble() ?? 0.0,
          if (payload['notes'] != null) 'notes': payload['notes'],
        },
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        await _offlineQueue.removeByClientId(item['clientId'] as String);
        return;
      }
      rethrow;
    }
  }

  /// Upload one queued daily study log row.
  Future<void> flushQueuedStudyLog(Map<String, dynamic> item) async {
    final payload = item['payload'];
    if (payload is! Map<String, dynamic>) {
      await _offlineQueue.removeByClientId(item['clientId'] as String);
      return;
    }
    final studyDate = payload['studyDate'] as String?;
    final hoursStudied = (payload['hoursStudied'] as num?)?.toDouble();
    if (studyDate == null || hoursStudied == null) {
      await _offlineQueue.removeByClientId(item['clientId'] as String);
      return;
    }

    ApiCallTracker.instance.record('POST ${ApiEndpoints.logStudy}');
    await _client.dio.post(
      ApiEndpoints.logStudy,
      data: {
        'studyDate': studyDate,
        'hoursStudied': hoursStudied,
        'topicsCompleted': (payload['topicsCompleted'] as num?)?.toInt() ?? 0,
      },
    );
  }

  Future<void> logStudyHours({
    required String studyDate,
    required double hoursStudied,
    int topicsCompleted = 0,
  }) async {
    await _offlineQueue.enqueue(
      entityType: 'STUDY_LOG',
      entityId: studyDate,
      action: 'LOG_STUDY_HOURS',
      payload: {
        'studyDate': studyDate,
        'hoursStudied': hoursStudied,
        'topicsCompleted': topicsCompleted,
      },
    );
  }

  /// Updates cached subject detail immediately (no network).
  Future<SubjectDetailModel?> patchTopicInCache({
    required int subjectId,
    required int topicId,
    double? actualHours,
    bool? isCompleted,
    String? status,
  }) async {
    final data = _store.getJson(_store.subjectDetailKey(subjectId));
    if (data == null) return null;

    final chapters = data['chapters'];
    if (chapters is! List) return null;

    for (final chapter in chapters) {
      if (chapter is! Map<String, dynamic>) continue;
      final topics = chapter['topics'];
      if (topics is! List) continue;
      for (final topic in topics) {
        if (topic is! Map<String, dynamic>) continue;
        if (topic['id'] != topicId) continue;

        if (actualHours != null) topic['actualHours'] = actualHours;
        if (isCompleted != null) topic['isCompleted'] = isCompleted;
        if (status != null) {
          topic['status'] = status;
        } else if (isCompleted == true) {
          topic['status'] = 'COMPLETED';
        } else if (actualHours != null && actualHours > 0) {
          topic['status'] = 'IN_PROGRESS';
        }
      }
    }

    _recalculateSubjectStats(data);
    await _store.putJson(_store.subjectDetailKey(subjectId), data);
    return SubjectDetailModel.fromJson(data);
  }

  void _recalculateSubjectStats(Map<String, dynamic> data) {
    var totalTopics = 0;
    var completedTopics = 0;
    var totalStudyHours = 0.0;

    final chapters = data['chapters'];
    if (chapters is! List) return;

    for (final chapter in chapters) {
      if (chapter is! Map<String, dynamic>) continue;
      var chTotal = 0;
      var chCompleted = 0;

      final topics = chapter['topics'];
      if (topics is List) {
        for (final topic in topics) {
          if (topic is! Map<String, dynamic>) continue;
          chTotal++;
          totalTopics++;
          totalStudyHours +=
              ((topic['actualHours'] as num?) ?? 0).toDouble();
          if (topic['isCompleted'] == true) {
            chCompleted++;
            completedTopics++;
          }
        }
      }

      chapter['totalTopics'] = chTotal;
      chapter['completedTopics'] = chCompleted;
      chapter['completionPercent'] =
          chTotal == 0 ? 0.0 : (chCompleted * 100.0 / chTotal);
    }

    data['totalTopics'] = totalTopics;
    data['completedTopics'] = completedTopics;
    data['completionPercent'] =
        totalTopics == 0 ? 0.0 : (completedTopics * 100.0 / totalTopics);
    data['totalStudyHours'] = totalStudyHours;
  }

  /// Fire-and-forget: patch local cache then queue for SYNC.
  void persistTopicProgressInBackground({
    required int subjectId,
    required int topicId,
    required bool isCompleted,
    required double actualHours,
    double? studyHoursDelta,
    String? studyDate,
  }) {
    unawaited(_persistLocally(
      subjectId: subjectId,
      topicId: topicId,
      isCompleted: isCompleted,
      actualHours: actualHours,
      studyHoursDelta: studyHoursDelta,
      studyDate: studyDate,
    ));
  }

  Future<void> _persistLocally({
    required int subjectId,
    required int topicId,
    required bool isCompleted,
    required double actualHours,
    double? studyHoursDelta,
    String? studyDate,
  }) async {
    await patchTopicInCache(
      subjectId: subjectId,
      topicId: topicId,
      actualHours: actualHours,
      isCompleted: isCompleted,
      status: isCompleted ? 'COMPLETED' : (actualHours > 0 ? 'IN_PROGRESS' : null),
    );
    await markTopicComplete(
      topicId: topicId,
      isCompleted: isCompleted,
      actualHours: actualHours,
    );
    if (studyHoursDelta != null && studyHoursDelta > 0 && studyDate != null) {
      await logStudyHours(
        studyDate: studyDate,
        hoursStudied: studyHoursDelta,
      );
    }
  }

  Future<List<TopicModel>> getTopicsByChapter(int chapterId) async {
    throw UnimplementedError('Use cached subject detail offline.');
  }
}
