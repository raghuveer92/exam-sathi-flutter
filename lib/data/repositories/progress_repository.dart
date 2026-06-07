import 'dart:async';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../models/subject_detail_model.dart';
import '../models/topic_model.dart';
import '../../core/local/api_call_tracker.dart';
import '../../core/local/local_store.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/sync/local_tables.dart';
import '../../core/sync/offline_queue_service.dart';
import '../../core/sync/progress_rebuild_service.dart';
import 'dashboard_repository.dart';

/// All reads from local cache. All writes to cache + pending sync queue.
class ProgressRepository {
  ProgressRepository({
    required ApiClient client,
    required LocalStore store,
    required OfflineQueueService offlineQueue,
    required DashboardRepository dashboardRepository,
    required ProgressRebuildService progressRebuildService,
  })  : _client = client,
        _store = store,
        _offlineQueue = offlineQueue,
        _dashboardRepository = dashboardRepository,
        _progressRebuildService = progressRebuildService;

  final ApiClient _client;
  final LocalStore _store;
  final OfflineQueueService _offlineQueue;
  final DashboardRepository _dashboardRepository;
  final ProgressRebuildService _progressRebuildService;
  final _uuid = const Uuid();

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
      final localMap = _store.getJson(_store.subjectDetailKey(subjectId));
      final merged = _mergeSubjectDetailWithLocal(data, localMap);
      await _store.putJson(_store.subjectDetailKey(subjectId), merged);
      return SubjectDetailModel.fromJson(merged);
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

  /// Merge server subject detail without discarding higher local topic hours.
  Map<String, dynamic> _mergeSubjectDetailWithLocal(
    Map<String, dynamic> remote,
    Map<String, dynamic>? local,
  ) {
    if (local == null) return remote;

    final localTopics = <int, Map<String, dynamic>>{};
    final localChapters = local['chapters'];
    if (localChapters is List) {
      for (final chapter in localChapters) {
        if (chapter is! Map<String, dynamic>) continue;
        final topics = chapter['topics'];
        if (topics is! List) continue;
        for (final topic in topics) {
          if (topic is! Map<String, dynamic>) continue;
          final id = (topic['id'] as num?)?.toInt();
          if (id != null) localTopics[id] = topic;
        }
      }
    }

    final merged = Map<String, dynamic>.from(remote);
    final remoteChapters = merged['chapters'];
    if (remoteChapters is! List) return merged;

    for (final chapter in remoteChapters) {
      if (chapter is! Map<String, dynamic>) continue;
      final topics = chapter['topics'];
      if (topics is! List) continue;
      for (final topic in topics) {
        if (topic is! Map<String, dynamic>) continue;
        final id = (topic['id'] as num?)?.toInt();
        if (id == null) continue;
        final localTopic = localTopics[id];
        if (localTopic == null) continue;

        final localHours =
            ((localTopic['actualHours'] as num?) ?? 0).toDouble();
        final remoteHours = ((topic['actualHours'] as num?) ?? 0).toDouble();
        if (localHours > remoteHours) {
          topic['actualHours'] = localHours;
        }
        if (localTopic['isCompleted'] == true) {
          topic['isCompleted'] = true;
          topic['status'] = 'COMPLETED';
        } else if (localHours > remoteHours && localHours > 0) {
          topic['status'] = localTopic['status'] ?? 'IN_PROGRESS';
        }
      }
    }

    _recalculateSubjectStats(merged);
    return merged;
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
      await markTopicProgressSynced(topicId);
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
    int? topicId,
  }) async {
    final sessionId = _uuid.v4();
    await _offlineQueue.enqueue(
      entityType: 'STUDY_LOG',
      entityId: '$studyDate-$sessionId',
      action: 'LOG_STUDY_HOURS',
      payload: {
        'sessionId': sessionId,
        if (topicId != null) 'topicId': topicId,
        'studyDate': studyDate,
        'hoursStudied': hoursStudied,
        'topicsCompleted': topicsCompleted,
        'createdAt': DateTime.now().toIso8601String(),
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
  /// Fire-and-forget wrapper — prefer [persistTopicProgress] when UI must stay in sync.
  void persistTopicProgressInBackground({
    required int subjectId,
    required int topicId,
    required bool wasCompleted,
    required bool isCompleted,
    required double actualHours,
    double? studyHoursDelta,
    String? studyDate,
  }) {
    unawaited(persistTopicProgress(
      subjectId: subjectId,
      topicId: topicId,
      wasCompleted: wasCompleted,
      isCompleted: isCompleted,
      actualHours: actualHours,
      studyHoursDelta: studyHoursDelta,
      studyDate: studyDate,
    ));
  }

  Future<void> persistTopicProgress({
    required int subjectId,
    required int topicId,
    required bool wasCompleted,
    required bool isCompleted,
    required double actualHours,
    double? studyHoursDelta,
    String? studyDate,
  }) =>
      _persistLocally(
        subjectId: subjectId,
        topicId: topicId,
        wasCompleted: wasCompleted,
        isCompleted: isCompleted,
        actualHours: actualHours,
        studyHoursDelta: studyHoursDelta,
        studyDate: studyDate,
      );

  Future<void> _persistLocally({
    required int subjectId,
    required int topicId,
    required bool wasCompleted,
    required bool isCompleted,
    required double actualHours,
    double? studyHoursDelta,
    String? studyDate,
  }) async {
    final detail = await patchTopicInCache(
      subjectId: subjectId,
      topicId: topicId,
      actualHours: actualHours,
      isCompleted: isCompleted,
      status: isCompleted ? 'COMPLETED' : (actualHours > 0 ? 'IN_PROGRESS' : null),
    );
    if (detail == null) return;

    await markTopicComplete(
      topicId: topicId,
      isCompleted: isCompleted,
      actualHours: actualHours,
    );
    await _writeTopicProgressRecord(
      topicId: topicId,
      subjectId: subjectId,
      isCompleted: isCompleted,
      actualHours: actualHours,
      syncStatus: LocalTables.syncStatusPending,
    );
    if (studyHoursDelta != null && studyHoursDelta != 0 && studyDate != null) {
      await logStudyHours(
        studyDate: studyDate,
        hoursStudied: studyHoursDelta,
        topicId: topicId,
      );
      await _writeDailyStudyLogRecord(
        studyDate: studyDate,
        hoursDelta: studyHoursDelta,
        topicsDelta: isCompleted && !wasCompleted ? 1 : 0,
        syncStatus: LocalTables.syncStatusPending,
      );
    }

    await _dashboardRepository.applyLocalProgressUpdate(
      subjectDetail: detail,
      wasCompleted: wasCompleted,
      isCompleted: isCompleted,
      studyHoursDelta: studyHoursDelta ?? 0,
      studyDate: studyDate ?? _localTodayDate(),
    );

    final examId = await _resolveExamIdForSubject(subjectId);
    if (examId != null) {
      await _progressRebuildService.rebuildAll();
    }
  }

  Future<int?> _resolveExamIdForSubject(int subjectId) async {
    final exams = await _dashboardRepository.resolveMyExamsFromCache();
    for (final exam in exams) {
      final subjects = _dashboardRepository.resolveVisibleSubjects(exam.examId);
      if (subjects.any((s) => s.id == subjectId)) return exam.examId;
    }
    return null;
  }

  /// Apply server-side study_progress rows from sync bundle (table-level merge).
  Future<void> applySyncedTopicProgress(List<dynamic> items) async {
    if (items.isEmpty) return;

    for (final raw in items) {
      if (raw is! Map<String, dynamic>) continue;
      final topicId = (raw['topicId'] as num?)?.toInt();
      final subjectId = (raw['subjectId'] as num?)?.toInt();
      if (topicId == null || subjectId == null) continue;

      if (_hasPendingTopicProgress(topicId)) continue;

      final isCompleted = raw['isCompleted'] as bool? ?? false;
      final actualHours = (raw['actualHours'] as num?)?.toDouble() ?? 0.0;
      final status = raw['status'] as String?;

      await patchTopicInCache(
        subjectId: subjectId,
        topicId: topicId,
        actualHours: actualHours,
        isCompleted: isCompleted,
        status: status,
      );

      await _writeTopicProgressRecord(
        topicId: topicId,
        subjectId: subjectId,
        isCompleted: isCompleted,
        actualHours: actualHours,
        syncStatus: LocalTables.syncStatusSynced,
        updatedAt: raw['updatedAt'] as String?,
      );
    }
  }

  bool _hasPendingTopicProgress(int topicId) {
    for (final item in _offlineQueue.pendingItems) {
      final action = item['action'] as String?;
      final payload = item['payload'];
      if (payload is! Map<String, dynamic>) continue;
      if ((payload['topicId'] as num?)?.toInt() != topicId) continue;
      if (action == 'COMPLETE_TOPIC' ||
          action == 'ADD_STUDY_HOURS' ||
          item['type'] == 'TOPIC_PROGRESS') {
        return true;
      }
    }
    return false;
  }

  Future<void> _writeTopicProgressRecord({
    required int topicId,
    required int subjectId,
    required bool isCompleted,
    required double actualHours,
    required String syncStatus,
    String? updatedAt,
  }) async {
    final table = Map<String, dynamic>.from(
      _store.getJson(LocalTables.topicProgress) ?? {},
    );
    table['$topicId'] = {
      'topicId': topicId,
      'subjectId': subjectId,
      'isCompleted': isCompleted,
      'actualHours': actualHours,
      'syncStatus': syncStatus,
      'updatedAt': updatedAt ?? DateTime.now().toIso8601String(),
    };
    await _store.putJson(LocalTables.topicProgress, table);
  }

  Future<void> _writeDailyStudyLogRecord({
    required String studyDate,
    required double hoursDelta,
    required int topicsDelta,
    required String syncStatus,
  }) async {
    final table = Map<String, dynamic>.from(
      _store.getJson(LocalTables.dailyStudyLogs) ?? {},
    );
    final existing = table[studyDate];
    final prevHours = existing is Map<String, dynamic>
        ? ((existing['hoursStudied'] as num?) ?? 0).toDouble()
        : 0.0;
    final prevTopics = existing is Map<String, dynamic>
        ? ((existing['topicsCompleted'] as num?) ?? 0).toInt()
        : 0;
    table[studyDate] = {
      'studyDate': studyDate,
      'hoursStudied': prevHours + hoursDelta,
      'topicsCompleted': prevTopics + topicsDelta,
      'syncStatus': syncStatus,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    await _store.putJson(LocalTables.dailyStudyLogs, table);
  }

  Future<void> markTopicProgressSynced(int topicId) async {
    final table = Map<String, dynamic>.from(
      _store.getJson(LocalTables.topicProgress) ?? {},
    );
    final row = table['$topicId'];
    if (row is Map<String, dynamic>) {
      row['syncStatus'] = LocalTables.syncStatusSynced;
      table['$topicId'] = row;
      await _store.putJson(LocalTables.topicProgress, table);
    }
  }

  String _localTodayDate() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  Future<List<TopicModel>> getTopicsByChapter(int chapterId) async {
    throw UnimplementedError('Use cached subject detail offline.');
  }
}
