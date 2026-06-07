import 'dart:async';

import 'package:logger/logger.dart';

import '../local/local_store.dart';
import '../network/connectivity_helper.dart';
import '../../data/models/subject_progress_model.dart';
import '../../data/repositories/auth_repository.dart';
import '../../core/sync/progress_rebuild_service.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../data/repositories/mock_test_repository.dart';
import '../../data/repositories/progress_repository.dart';
import '../../data/repositories/sync_repository.dart';
import 'sync_download_stats.dart';
import 'offline_queue_service.dart';
import 'sync_progress.dart';

enum SyncStatus { idle, syncing, success, failed, offline }

/// Manual-sync-only orchestrator. No automatic background sync.
class SyncService {
  SyncService({
    required LocalStore store,
    required SyncRepository syncRepository,
    required OfflineQueueService offlineQueue,
    required AuthRepository authRepository,
    required DashboardRepository dashboardRepository,
    required ProgressRepository progressRepository,
    required ProgressRebuildService progressRebuildService,
    required MockTestRepository mockTestRepository,
    required Logger logger,
  })  : _store = store,
        _syncRepository = syncRepository,
        _offlineQueue = offlineQueue,
        _authRepository = authRepository,
        _dashboardRepository = dashboardRepository,
        _progressRepository = progressRepository,
        _progressRebuildService = progressRebuildService,
        _mockTestRepository = mockTestRepository,
        _logger = logger;

  final LocalStore _store;
  final SyncRepository _syncRepository;
  final OfflineQueueService _offlineQueue;
  final AuthRepository _authRepository;
  final DashboardRepository _dashboardRepository;
  final ProgressRepository _progressRepository;
  final ProgressRebuildService _progressRebuildService;
  final MockTestRepository _mockTestRepository;
  final Logger _logger;

  Completer<void>? _activeSync;
  SyncStatus _status = SyncStatus.idle;
  String? _lastError;

  SyncStatus get status => _status;
  String? get lastError => _lastError;
  bool get isSyncing => _activeSync != null;

  final _statusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _statusController.stream;

  /// No-op — automatic sync disabled; user controls sync via SYNC button.
  void startConnectivityListener() {}

  Future<void> dispose() async {
    await _statusController.close();
  }

  DateTime? get lastBundleSync {
    final raw = _store.getString(LocalStore.syncBundleAtKey);
    return raw != null ? DateTime.tryParse(raw) : null;
  }

  Future<bool> isOnline() => isDeviceOnline();

  void _setStatus(SyncStatus status) {
    _status = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
    unawaited(_store.putJson(LocalStore.syncStatusKey, {
      'status': status.name,
      'error': _lastError,
      'at': DateTime.now().toIso8601String(),
    }));
  }

  void _emit(SyncStep step, void Function(SyncProgress) onProgress,
      {int current = 0, int total = 0, String? detail}) {
    onProgress(SyncProgress(
      step: step,
      current: current,
      total: total,
      detail: detail,
    ));
  }

  /// First-time download after login/signup.
  Future<void> initialDownload({
    required void Function(SyncProgress progress) onProgress,
  }) async {
    if (!await isOnline()) {
      throw StateError('Internet required for initial download.');
    }
    await _downloadAll(onProgress: onProgress, incremental: false);
    _emit(SyncStep.complete, onProgress);
    _setStatus(SyncStatus.success);
  }

  /// User-triggered SYNC: upload pending → download latest.
  Future<void> manualSync() async {
    if (_activeSync != null) return _activeSync!.future;
    if (!await isOnline()) {
      _setStatus(SyncStatus.offline);
      throw StateError('No internet connection. Connect to sync.');
    }

    final completer = Completer<void>();
    _activeSync = completer;
    _lastError = null;
    _setStatus(SyncStatus.syncing);

    var uploadOk = true;
    try {
      uploadOk = await _uploadPending((p) {});
      if (uploadOk) {
        await _downloadAll(
          onProgress: (_) {},
          incremental: true,
        );
      } else {
        _logger.w('Skipping download — pending study changes were not uploaded');
      }
      await _offlineQueue.discardResolvedActiveExamItems();
      _offlineQueue.refreshPendingCount();
      if (!uploadOk) {
        _lastError = 'Some offline changes could not be uploaded';
        _setStatus(SyncStatus.failed);
      } else {
        _setStatus(SyncStatus.success);
      }
    } catch (e, st) {
      _lastError = e.toString();
      _logger.w('Manual sync failed', error: e, stackTrace: st);
      _setStatus(SyncStatus.failed);
      rethrow;
    } finally {
      completer.complete();
      _activeSync = null;
    }
  }

  Future<bool> _uploadPending(void Function(SyncProgress) onProgress) async {
    _emit(SyncStep.uploading, onProgress);
    var allOk = true;

    await _coalesceSupersededTopicProgressItems();
    await _coalescePendingStudyLogs();

    for (final item in List<Map<String, dynamic>>.from(_offlineQueue.pendingItems)) {
      final action = item['action'] as String?;
      final type = item['type'] as String? ?? action;
      final clientId = item['clientId'] as String?;
      if (clientId == null) continue;

      try {
        if (action == 'SUBMIT_TEST') {
          await _mockTestRepository.flushQueuedSubmit(item);
        } else if (action == 'SET_ACTIVE_EXAM') {
          await _dashboardRepository.flushQueuedActiveExam(item);
        } else if (action == 'COMPLETE_TOPIC' ||
            action == 'ADD_STUDY_HOURS' ||
            type == 'TOPIC_PROGRESS') {
          await _progressRepository.flushQueuedTopicProgress(item);
        } else if (action == 'LOG_STUDY_HOURS' || type == 'LOG_STUDY') {
          await _progressRepository.flushQueuedStudyLog(item);
        } else if (action == 'STUDY_HOURS') {
          final hours =
              (item['payload']?['dailyTargetHours'] as num?)?.toDouble();
          if (hours != null) {
            await _dashboardRepository.updateStudyHours(hours);
          }
        } else {
          continue;
        }
        await _offlineQueue.removeByClientId(clientId);
      } catch (e, st) {
        allOk = false;
        _logger.w('Queue item flush failed action=$action', error: e, stackTrace: st);
      }
    }

    final restOk = await _offlineQueue.flush();
    return allOk && restOk;
  }

  /// Drop older topic-progress rows when a newer row exists for the same topic.
  Future<void> _coalesceSupersededTopicProgressItems() async {
    final pending = _offlineQueue.pendingItems;
    final latestByTopic = <String, String>{};

    for (final item in pending) {
      if (!_isTopicProgressItem(item)) continue;
      final payload = item['payload'];
      if (payload is! Map<String, dynamic>) continue;
      final topicId = payload['topicId']?.toString();
      final userExamId = payload['userExamId']?.toString() ?? '';
      final clientId = item['clientId'] as String?;
      if (topicId == null || clientId == null) continue;
      latestByTopic['$userExamId:$topicId'] = clientId;
    }

    for (final item in pending) {
      if (!_isTopicProgressItem(item)) continue;
      final payload = item['payload'];
      if (payload is! Map<String, dynamic>) continue;
      final topicId = payload['topicId']?.toString();
      final userExamId = payload['userExamId']?.toString() ?? '';
      final clientId = item['clientId'] as String?;
      if (topicId == null || clientId == null) continue;
      if (latestByTopic['$userExamId:$topicId'] != clientId) {
        await _offlineQueue.removeByClientId(clientId);
      }
    }
  }

  bool _isTopicProgressItem(Map<String, dynamic> item) {
    final action = item['action'] as String?;
    final type = item['type'] as String? ?? action;
    return action == 'COMPLETE_TOPIC' ||
        action == 'ADD_STUDY_HOURS' ||
        type == 'TOPIC_PROGRESS';
  }

  bool _isStudyLogItem(Map<String, dynamic> item) {
    final action = item['action'] as String?;
    final type = item['type'] as String? ?? action;
    return action == 'LOG_STUDY_HOURS' || type == 'LOG_STUDY';
  }

  /// Sum pending daily study-log deltas per date into one upload row.
  Future<void> _coalescePendingStudyLogs() async {
    final pending = _offlineQueue.pendingItems;
    final sumsByDate = <String, _StudyLogAggregate>{};

    for (final item in pending) {
      if (!_isStudyLogItem(item)) continue;
      final payload = item['payload'];
      if (payload is! Map<String, dynamic>) continue;
      final studyDate = payload['studyDate'] as String?;
      final hours = (payload['hoursStudied'] as num?)?.toDouble();
      if (studyDate == null || hours == null) continue;

      final agg = sumsByDate.putIfAbsent(studyDate, _StudyLogAggregate.new);
      agg.hours += hours;
      agg.topics += (payload['topicsCompleted'] as num?)?.toInt() ?? 0;
      agg.clientIds.add(item['clientId'] as String);
      agg.keepClientId ??= item['clientId'] as String?;
      agg.payloadTemplate = payload;
    }

    for (final entry in sumsByDate.entries) {
      if (entry.value.clientIds.length <= 1) continue;

      final studyDate = entry.key;
      final agg = entry.value;
      final keepId = agg.keepClientId;
      if (keepId == null) continue;

      for (final clientId in agg.clientIds) {
        if (clientId != null && clientId != keepId) {
          await _offlineQueue.removeByClientId(clientId);
        }
      }

      await _offlineQueue.updatePayloadByClientId(keepId, {
        ...?agg.payloadTemplate,
        'studyDate': studyDate,
        'hoursStudied': agg.hours,
        'topicsCompleted': agg.topics,
      });
    }
  }

  Future<void> _downloadAll({
    required void Function(SyncProgress progress) onProgress,
    required bool incremental,
  }) async {
    _emit(SyncStep.preparing, onProgress);
    final stats = SyncDownloadStats();

    _emit(SyncStep.userData, onProgress);
    try {
      await _authRepository.getMe();
    } catch (e, st) {
      _logger.w('Profile refresh skipped before sync', error: e, stackTrace: st);
    }
    try {
      stats.studyProgressRows = await syncBundle(incremental: incremental);
    } catch (e, st) {
      _logger.w('Bundle sync failed, using legacy APIs', error: e, stackTrace: st);
      await syncLegacyFallback();
    }

    final exams = await _dashboardRepository.resolveMyExamsFromCache();
    stats.exams = exams.length;
    var subjectCount = 0;
    for (final exam in exams) {
      subjectCount += (await _dashboardRepository.getVisibleSubjectsByExam(
        exam.examId,
        forceRemote: false,
      )).length;
    }
    if (subjectCount == 0) subjectCount = 1;

    var subjectIndex = 0;
    _emit(SyncStep.subjects, onProgress, current: 0, total: subjectCount);

    for (final exam in exams) {
      if (!exam.isActive) {
        try {
          await _dashboardRepository.setActiveMyExam(exam.id);
        } catch (e, st) {
          _logger.w(
            'Could not set active exam ${exam.id} before subject download',
            error: e,
            stackTrace: st,
          );
        }
      }

      final subjects = await _dashboardRepository.resolveSubjectsForExam(
        exam.examId,
        forceRemote: true,
      );
      stats.subjects += subjects.length;
      _logger.i(
        'Exam ${exam.examName} (userExam ${exam.id}): ${subjects.length} subjects',
      );
      for (final subject in subjects) {
        subjectIndex++;
        _emit(
          SyncStep.chapters,
          onProgress,
          current: subjectIndex,
          total: subjectCount,
          detail: subject.name,
        );
        try {
          final detail = await _progressRepository.getSubjectDetail(
            subject.id,
            userExamId: exam.id,
            forceRemote: true,
          );
          for (final chapter in detail.chapters) {
            stats.topics += chapter.topics.length;
          }
        } catch (e, st) {
          _logger.w('Subject ${subject.id} download skipped',
              error: e, stackTrace: st);
        }
      }
    }

    _emit(SyncStep.topics, onProgress, current: subjectCount, total: subjectCount);

    await syncCatalog(incremental: incremental);

    await _progressRepository.applyTopicProgressTableToSubjectDetails();
    stats.dailyStudyLogs =
        await _progressRepository.downloadWeeklyStudyLogs();

    final topicIds = await _collectTopicIds();
    _emit(SyncStep.mockTests, onProgress, current: 0, total: topicIds.length);

    var topicIndex = 0;
    for (final topicId in topicIds) {
      topicIndex++;
      _emit(
        SyncStep.questions,
        onProgress,
        current: topicIndex,
        total: topicIds.length,
        detail: 'Topic $topicId',
      );
      try {
        await _mockTestRepository.syncTopicForOffline(topicId);
        stats.mockTests++;
      } catch (e, st) {
        _logger.w('Mock test sync skipped $topicId', error: e, stackTrace: st);
      }
    }
    stats.questions = stats.mockTests;

    _emit(SyncStep.progress, onProgress);
    try {
      await _mockTestRepository.getPerformance(forceRemote: true);
    } catch (_) {}
    await _progressRebuildService.rebuildAll();
    stats.log(_logger);
  }

  Future<List<int>> _collectTopicIds() async {
    final ids = <int>{};
    final exams = await _dashboardRepository.resolveMyExamsFromCache();
    for (final exam in exams) {
      final subjects = await _dashboardRepository.getVisibleSubjectsByExam(
        exam.examId,
        forceRemote: false,
      );
      for (final subject in subjects) {
        final detail = await _progressRepository.getSubjectDetailCached(
          subject.id,
          userExamId: exam.id,
        );
        if (detail == null) continue;
        for (final chapter in detail.chapters) {
          for (final topic in chapter.topics) {
            ids.add(topic.id);
          }
        }
      }
    }
    return ids.toList();
  }

  Future<void> syncLegacyFallback() async {
    await _dashboardRepository.fetchDashboardFromNetwork();
    final exams = await _dashboardRepository.getMyExams(forceRemote: true);
    for (final exam in exams) {
      await _dashboardRepository.getSubjectProgressByExam(
        exam.examId,
        forceRemote: true,
      );
      await _dashboardRepository.getVisibleSubjectsByExam(
        exam.examId,
        forceRemote: true,
      );
    }
    await _store.putString(
      LocalStore.syncBundleAtKey,
      DateTime.now().toIso8601String(),
    );
  }

  /// Returns count of ingested study_progress rows from bundle.
  Future<int> syncBundle({bool incremental = false}) async {
    final since = incremental ? lastBundleSync : null;
    final data = await _syncRepository.syncBundle(since: since);

    final dashboard = data['dashboard'];
    final myExams = data['myExams'];
    final profileUser = _store.getJson(LocalStore.userProfileKey);

    if (dashboard is Map<String, dynamic>) {
      await _dashboardRepository.storeSyncedDashboard(
        dashboard,
        bundleMyExams: myExams as List<dynamic>?,
        profileUser: profileUser,
      );
    } else if (myExams is List && myExams.isNotEmpty) {
      final existing = _store.getJson(LocalStore.dashboardKey);
      final base = existing ?? <String, dynamic>{
        'user': profileUser ?? {},
        'subjectProgress': [],
        'weeklyLogs': [],
      };
      await _dashboardRepository.storeSyncedDashboard(
        Map<String, dynamic>.from(base),
        bundleMyExams: myExams,
        profileUser: profileUser,
      );
    }

    if (myExams is List) {
      await _store.putJson(LocalStore.myExamsKey, myExams);
    }

    try {
      await _authRepository.getMe();
    } catch (_) {}

    await _dashboardRepository.syncDailyTargetFromProfile();

    final progressMap = data['subjectProgressByExamId'];
    if (progressMap is Map) {
      for (final entry in progressMap.entries) {
        final examId = int.tryParse(entry.key.toString());
        if (examId == null) continue;
        final remote = entry.value as List<dynamic>;
        final local = _store.getJsonList(_store.subjectProgressKey(examId));
        final merged = _dashboardRepository.mergeSubjectProgressLists(
          local,
          remote,
        );
        await _store.putJson(_store.subjectProgressKey(examId), merged);

        final visible = _dashboardRepository.getVisibleSubjectsCached(examId);
        if (visible == null || visible.isEmpty) {
          final subjects = merged
              .whereType<Map<String, dynamic>>()
              .map(
                (row) => SubjectProgressModel.fromJson(row)
                    .toSubjectModel(examId),
              )
              .toList();
          if (subjects.isNotEmpty) {
            await _store.putJson(
              _store.visibleSubjectsKey(examId),
              subjects.map((s) => s.toJson()).toList(),
            );
          }
        }
      }
    }

    var ingestedProgress = 0;
    final changedProgress = data['changedProgress'];
    if (changedProgress is List && changedProgress.isNotEmpty) {
      ingestedProgress =
          await _progressRepository.ingestSyncedTopicProgress(changedProgress);
    }

    final serverTime = data['serverTime'] as String?;
    if (serverTime != null) {
      await _store.putString(LocalStore.syncBundleAtKey, serverTime);
    }
    return ingestedProgress;
  }

  Future<void> syncCatalog({bool incremental = false}) async {
    final raw = _store.getString(LocalStore.syncCatalogAtKey);
    final since = incremental && raw != null ? DateTime.tryParse(raw) : null;
    final data = await _syncRepository.syncCatalog(since: since);
    await _store.putJson(LocalStore.syncCatalogMasterKey, data);
    final serverTime = data['serverTime'] as String?;
    if (serverTime != null) {
      await _store.putString(LocalStore.syncCatalogAtKey, serverTime);
    }

    final exams = await _dashboardRepository.resolveMyExamsFromCache();
    for (final exam in exams) {
      final subjects = await _dashboardRepository.getVisibleSubjectsByExam(
        exam.examId,
        forceRemote: false,
      );
      if (subjects.isNotEmpty) {
        await _progressRepository.materializeSubjectDetailsFromCatalog(
          userExamId: exam.id,
          subjectIds: subjects.map((s) => s.id),
        );
      }
    }
  }

  /// Deprecated — use [manualSync]. Kept for compatibility.
  Future<void> refreshAll({bool force = true}) => manualSync();

  /// Deprecated — no automatic sync.
  Future<void> fullInitialSync({bool incremental = false, bool force = false}) =>
      manualSync();
}

class _StudyLogAggregate {
  double hours = 0;
  int topics = 0;
  final clientIds = <String?>[];
  String? keepClientId;
  Map<String, dynamic>? payloadTemplate;
}
