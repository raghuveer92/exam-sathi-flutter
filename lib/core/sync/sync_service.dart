import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
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
import 'sync_queue_constants.dart';

enum SyncStatus { idle, syncing, success, failed, offline }

/// Offline-first sync engine — local DB is source of truth; server is backup.
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
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _debounceTimer;
  bool _wasOnline = true;

  SyncStatus get status => _status;
  String? get lastError => _lastError;
  bool get isSyncing => _activeSync != null;

  final _statusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _statusController.stream;

  /// Listens for offline → online and triggers background sync automatically.
  void startConnectivityListener() {
    _connectivitySub?.cancel();
    final sub = listenForConnectivity((online) {
      if (online && !_wasOnline) {
        scheduleBackgroundSync();
      } else if (!online) {
        _setStatus(_offlineQueue.pendingCount > 0
            ? SyncStatus.offline
            : SyncStatus.idle);
      }
      _wasOnline = online;
    });
    if (sub != null) {
      _connectivitySub = sub;
    }
  }

  /// Debounced entry point — safe to call from UI, auth, or queue enqueue.
  void scheduleBackgroundSync({bool fullDownload = false}) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(runBackgroundSync(fullDownload: fullDownload));
    });
  }

  /// Non-blocking background sync — never throws to callers.
  Future<void> runBackgroundSync({bool fullDownload = false}) async {
    if (_activeSync != null) return _activeSync!.future;
    if (!await _authRepository.isLoggedIn()) return;

    if (!await isOnline()) {
      _setStatus(_offlineQueue.pendingCount > 0
          ? SyncStatus.offline
          : SyncStatus.idle);
      return;
    }

    try {
      await _executeSync(
        silent: true,
        fullDownload: fullDownload,
      );
    } catch (e, st) {
      _logger.w('Background sync failed', error: e, stackTrace: st);
    }
  }

  Future<void> dispose() async {
    _debounceTimer?.cancel();
    await _connectivitySub?.cancel();
    await _statusController.close();
  }

  DateTime? get lastSyncTime => _store.getLastSyncTime();

  DateTime? get lastBundleSync => lastSyncTime;

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

  /// First-time full download after login/signup.
  Future<void> initialDownload({
    required void Function(SyncProgress progress) onProgress,
  }) async {
    await downloadAllContent(onProgress: onProgress);
    _setStatus(SyncStatus.success);
  }

  /// Full content download — login, reset, or explicit re-download only.
  Future<void> downloadAllContent({
    required void Function(SyncProgress progress) onProgress,
  }) async {
    if (!await isOnline()) {
      throw StateError('Internet required to download exam content.');
    }
    await _downloadFull(onProgress: onProgress);
    _emit(SyncStep.complete, onProgress);
  }

  /// Download syllabus for a newly added enrollment without re-fetching everything.
  Future<void> downloadEnrollmentContent({
    required void Function(SyncProgress progress) onProgress,
    int? userExamId,
  }) async {
    if (!await isOnline()) {
      throw StateError('Internet required to download exam content.');
    }
    _emit(SyncStep.preparing, onProgress);

    final incremental = lastSyncTime != null;
    await syncBundle(incremental: incremental);
    final catalog = await syncCatalog(incremental: incremental);

    final exams = await _dashboardRepository.resolveMyExamsFromCache();
    final targets = userExamId != null
        ? exams.where((e) => e.id == userExamId)
        : exams.where((e) => e.isActive);

    for (final exam in targets) {
      final subjects = await _dashboardRepository.getVisibleSubjectsByExam(
        exam.examId,
        forceRemote: false,
      );
      if (subjects.isEmpty) continue;

      final subjectIds = subjects.map((s) => s.id).toList();
      await _progressRepository.materializeSubjectDetailsFromCatalog(
        userExamId: exam.id,
        subjectIds: subjectIds,
      );

      final touched = catalog.affectedSubjectIds
          .where((id) => subjectIds.contains(id))
          .toList();
      if (touched.isNotEmpty) {
        await _progressRepository.refreshSubjectDetailsFromCatalog(
          userExamId: exam.id,
          subjectIds: touched,
        );
      }
    }

    await _progressRepository.applyTopicProgressForEnrollments(
      targets.map((e) => e.id).toSet(),
    );
    await _progressRebuildService.rebuildExams(
      targets.map((e) => e.examId),
    );
    if (catalog.serverTime != null || incremental) {
      await _persistLastSyncTime(catalog.serverTime ?? _lastBundleServerTime);
    }
    _emit(SyncStep.complete, onProgress);
  }

  /// Wipes sync cursor and performs a complete re-download (profile action).
  Future<void> resetAndRedownload({
    required void Function(SyncProgress progress) onProgress,
  }) async {
    await _store.clearLastSyncTime();
    await _store.resetInitialDownloadComplete();
    await downloadAllContent(onProgress: onProgress);
    await _dashboardRepository.reconcileDashboardCache();
    await _progressRebuildService.rebuildAll();
    await _store.markInitialDownloadComplete();
  }

  /// Force sync now — same pipeline as background sync but surfaces errors.
  Future<void> manualSync({bool fullDownload = false}) async {
    if (_activeSync != null) return _activeSync!.future;
    if (!await isOnline()) {
      _setStatus(SyncStatus.offline);
      throw StateError('No internet connection. Connect to sync.');
    }
    await _executeSync(silent: false, fullDownload: fullDownload);
    if (_status == SyncStatus.failed) {
      throw StateError(_lastError ?? 'Sync failed');
    }
  }

  Future<void> _executeSync({
    required bool silent,
    required bool fullDownload,
  }) async {
    if (_activeSync != null) return _activeSync!.future;

    final completer = Completer<void>();
    _activeSync = completer;
    _lastError = null;
    _setStatus(SyncStatus.syncing);

    var uploadOk = true;
    try {
      uploadOk = await _uploadPending((p) {});
      if (fullDownload) {
        await downloadAllContent(onProgress: (_) {});
        await _dashboardRepository.reconcileDashboardCache();
        await _progressRebuildService.rebuildAll();
        await _store.markInitialDownloadComplete();
      } else {
        await _downloadIncremental(onProgress: (_) {});
      }
      await _offlineQueue.discardResolvedActiveExamItems();
      await _progressRepository.reconcileQueueWithSyncedState();
      _offlineQueue.refreshPendingCount();
      final pendingAfterSync = _offlineQueue.pendingCount;
      if (!uploadOk || pendingAfterSync > 0) {
        _lastError = pendingAfterSync > 0
            ? '$pendingAfterSync change(s) still waiting to sync'
            : 'Some offline changes could not be uploaded';
        _setStatus(SyncStatus.failed);
      } else {
        _setStatus(SyncStatus.success);
      }
    } catch (e, st) {
      _lastError = e.toString();
      _logger.w('Sync failed', error: e, stackTrace: st);
      _setStatus(SyncStatus.failed);
      if (!silent) rethrow;
    } finally {
      completer.complete();
      _activeSync = null;
    }
  }

  Future<bool> _uploadPending(void Function(SyncProgress) onProgress) async {
    _emit(SyncStep.uploading, onProgress);
    var allOk = true;

    await _offlineQueue.resetStuckSyncingItems();
    await _coalesceSupersededTopicProgressItems();
    await _coalescePendingStudyLogs();

    for (final item
        in List<Map<String, dynamic>>.from(_offlineQueue.processableItems)) {
      final action = item['action'] as String?;
      final type = item['type'] as String? ?? action;
      final clientId = item['clientId'] as String?;
      if (clientId == null) continue;

      await _offlineQueue.updateStatus(clientId, SyncQueueStatus.syncing);
      try {
        if (action == 'SUBMIT_TEST') {
          await _mockTestRepository.flushQueuedSubmit(item);
        } else if (action == 'SET_ACTIVE_EXAM') {
          await _dashboardRepository.flushQueuedActiveExam(item);
        } else if (action == 'UPDATE_EXAM_DATE') {
          await _dashboardRepository.flushQueuedExamDate(item);
        } else if (action == 'COMPLETE_TOPIC' ||
            action == 'ADD_STUDY_HOURS' ||
            type == 'TOPIC_PROGRESS') {
          await _progressRepository.flushQueuedTopicProgress(item);
        } else if (action == 'LOG_STUDY_HOURS' || type == 'LOG_STUDY') {
          await _progressRepository.flushQueuedStudyLog(item);
        } else {
          await _offlineQueue.updateStatus(clientId, SyncQueueStatus.pending);
          continue;
        }
        await _offlineQueue.removeByClientId(clientId);
      } catch (e, st) {
        allOk = false;
        await _offlineQueue.markFailed(clientId);
        _logger.w('Queue item flush failed action=$action',
            error: e, stackTrace: st);
      }
    }

    final purged = await _progressRepository.reconcileQueueWithSyncedState();
    if (purged > 0) {
      _logger.i('Purged $purged acknowledged queue item(s) after upload');
    }

    final restOk = await _offlineQueue.flush();
    final remaining = _offlineQueue.pendingCount;
    if (remaining > 0) {
      _logger.w('Upload finished with $remaining queue item(s) still pending');
    }
    return allOk && restOk && remaining == 0;
  }

  /// Drop older topic-progress rows when a newer row exists for the same topic.
  Future<void> _coalesceSupersededTopicProgressItems() async {
    final pending = _offlineQueue.processableItems;
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
    final pending = _offlineQueue.processableItems;
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

  /// WhatsApp-style delta download — bundle + catalog since [lastSyncTime] only.
  Future<void> _downloadIncremental({
    required void Function(SyncProgress progress) onProgress,
  }) async {
    _emit(SyncStep.preparing, onProgress);
    final stats = SyncDownloadStats();

    var affectedExamIds = <int>{};
    try {
      final progressRows = await syncBundle(incremental: true);
      stats.studyProgressRows = progressRows;
      affectedExamIds = _lastBundleAffectedExamIds ?? affectedExamIds;
    } catch (e, st) {
      _logger.w('Incremental bundle sync failed', error: e, stackTrace: st);
      rethrow;
    }

    final catalog = await syncCatalog(incremental: true);
    if (catalog.hadChanges && catalog.affectedSubjectIds.isNotEmpty) {
      final exams = await _dashboardRepository.resolveMyExamsFromCache();
      for (final exam in exams) {
        final subjects = await _dashboardRepository.getVisibleSubjectsByExam(
          exam.examId,
          forceRemote: false,
        );
        final subjectIds = subjects.map((s) => s.id).toSet();
        final touched = catalog.affectedSubjectIds
            .where(subjectIds.contains)
            .toList();
        if (touched.isEmpty) continue;
        await _progressRepository.refreshSubjectDetailsFromCatalog(
          userExamId: exam.id,
          subjectIds: touched,
        );
      }
    }

    final enrollmentIds = <int>{};
    for (final exam in await _dashboardRepository.resolveMyExamsFromCache()) {
      if (affectedExamIds.contains(exam.examId)) {
        enrollmentIds.add(exam.id);
      }
    }
    if (enrollmentIds.isNotEmpty) {
      await _progressRepository.applyTopicProgressForEnrollments(enrollmentIds);
    }

    if (affectedExamIds.isNotEmpty) {
      await _progressRebuildService.rebuildExams(affectedExamIds);
    } else if (stats.studyProgressRows > 0 || catalog.hadChanges) {
      await _progressRebuildService.rebuildAll();
    }

    await _persistLastSyncTime(catalog.serverTime ?? _lastBundleServerTime);
    stats.log(_logger);
  }

  Set<int>? _lastBundleAffectedExamIds;
  String? _lastBundleServerTime;

  Future<void> _downloadFull({
    required void Function(SyncProgress progress) onProgress,
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
      stats.studyProgressRows = await syncBundle(incremental: false);
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

    await syncCatalog(incremental: false);

    await _progressRepository.applyTopicProgressTableToSubjectDetails();
    stats.dailyStudyLogs =
        await _progressRepository.downloadWeeklyStudyLogs();

    await _mockTestRepository.clearOfflineCache();
    final mockTestTopicIds = _resolveMockTestTopicIds();
    _emit(
      SyncStep.mockTests,
      onProgress,
      current: 0,
      total: mockTestTopicIds.length,
    );

    var topicIndex = 0;
    for (final topicId in mockTestTopicIds) {
      topicIndex++;
      _emit(
        SyncStep.mockTests,
        onProgress,
        current: topicIndex,
        total: mockTestTopicIds.length,
        detail: 'Topic $topicId',
      );
      try {
        final questionCount =
            await _mockTestRepository.syncTopicForOffline(topicId);
        if (questionCount > 0) {
          stats.mockTests++;
          stats.questions += questionCount;
        }
      } catch (e, st) {
        _logger.w('Mock test sync skipped $topicId', error: e, stackTrace: st);
      }
    }

    _emit(SyncStep.progress, onProgress);
    try {
      await _mockTestRepository.getPerformance(forceRemote: true);
    } catch (_) {}
    await _progressRebuildService.rebuildAll();
    await _persistLastSyncTime(null);
    stats.log(_logger);
  }

  List<int> _resolveMockTestTopicIds() {
    final catalog = _store.getJson(LocalStore.syncCatalogMasterKey);
    final raw = catalog?['mockTestTopicIds'] as List<dynamic>?;
    if (raw == null || raw.isEmpty) return const [];
    return raw.map((e) => (e as num).toInt()).toList();
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
    final since = incremental ? lastSyncTime : null;
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

    await _dashboardRepository.reconcileDashboardCache();

    final progressMap = data['subjectProgressByExamId'];
    _lastBundleAffectedExamIds = <int>{};
    if (progressMap is Map) {
      for (final entry in progressMap.entries) {
        final examId = int.tryParse(entry.key.toString());
        if (examId == null) continue;
        _lastBundleAffectedExamIds!.add(examId);
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
      for (final raw in changedProgress) {
        if (raw is! Map<String, dynamic>) continue;
        final examId = (raw['examId'] as num?)?.toInt();
        if (examId != null) {
          _lastBundleAffectedExamIds!.add(examId);
        }
      }
    }

    final serverTime = data['serverTime'] as String?;
    _lastBundleServerTime = serverTime;
    if (serverTime != null && !incremental) {
      await _persistLastSyncTime(serverTime);
    }
    return ingestedProgress;
  }

  Future<CatalogSyncResult> syncCatalog({
    bool incremental = false,
    List<int>? examIds,
  }) async {
    final since = incremental ? lastSyncTime : null;
    final scopedExamIds = examIds ?? await _resolveEnrolledExamIds();
    final data = await _syncRepository.syncCatalog(
      since: since,
      examIds: scopedExamIds.isEmpty ? null : scopedExamIds,
    );
    final serverTime = data['serverTime'] as String?;

    if (incremental && since != null) {
      final hadChanges = _catalogDeltaHasChanges(data);
      if (hadChanges) {
        await _mergeCatalogDelta(data);
      }
      return CatalogSyncResult(
        hadChanges: hadChanges,
        affectedSubjectIds: _subjectIdsFromCatalogDelta(data),
        serverTime: serverTime,
      );
    }

    await _store.putJson(LocalStore.syncCatalogMasterKey, data);
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

    return CatalogSyncResult(
      hadChanges: true,
      affectedSubjectIds: _subjectIdsFromCatalogMaster(),
      serverTime: serverTime,
    );
  }

  Future<List<int>> _resolveEnrolledExamIds() async {
    final exams = await _dashboardRepository.resolveMyExamsFromCache();
    return exams.map((e) => e.examId).toSet().toList();
  }

  Future<void> _persistLastSyncTime(String? serverTime) async {
    final parsed = serverTime != null
        ? DateTime.tryParse(serverTime)
        : null;
    await _store.setLastSyncTime(parsed ?? DateTime.now());
  }

  bool _catalogDeltaHasChanges(Map<String, dynamic> delta) {
    for (final key in _catalogListKeys) {
      final list = delta[key];
      if (list is List && list.isNotEmpty) return true;
    }
    return false;
  }

  static const _catalogListKeys = [
    'categories',
    'exams',
    'subjects',
    'chapters',
    'topics',
  ];

  Future<void> _mergeCatalogDelta(Map<String, dynamic> delta) async {
    final existing = Map<String, dynamic>.from(
      _store.getJson(LocalStore.syncCatalogMasterKey) ?? {},
    );
    for (final key in _catalogListKeys) {
      _mergeJsonListById(existing, delta, key);
    }
    if (delta['mockTestTopicIds'] is List) {
      existing['mockTestTopicIds'] = delta['mockTestTopicIds'];
    }
    if (delta['serverTime'] != null) {
      existing['serverTime'] = delta['serverTime'];
    }
    await _store.putJson(LocalStore.syncCatalogMasterKey, existing);
  }

  void _mergeJsonListById(
    Map<String, dynamic> target,
    Map<String, dynamic> delta,
    String key,
  ) {
    final deltaList = delta[key];
    if (deltaList is! List || deltaList.isEmpty) return;

    final existingList = (target[key] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        [];
    final byId = <int, Map<String, dynamic>>{
      for (final row in existingList)
        if (row['id'] is num) (row['id'] as num).toInt(): row,
    };
    for (final raw in deltaList) {
      if (raw is! Map) continue;
      final id = raw['id'];
      if (id is! num) continue;
      byId[id.toInt()] = Map<String, dynamic>.from(raw);
    }
    target[key] = byId.values.toList();
  }

  Set<int> _subjectIdsFromCatalogDelta(Map<String, dynamic> delta) {
    final ids = <int>{};
    final subjects = delta['subjects'];
    if (subjects is List) {
      for (final raw in subjects) {
        if (raw is Map && raw['id'] is num) {
          ids.add((raw['id'] as num).toInt());
        }
      }
    }
    final chapters = delta['chapters'];
    if (chapters is List) {
      for (final raw in chapters) {
        if (raw is Map && raw['subjectId'] is num) {
          ids.add((raw['subjectId'] as num).toInt());
        }
      }
    }
    final topics = delta['topics'];
    if (topics is List) {
      final catalog = _store.getJson(LocalStore.syncCatalogMasterKey);
      final chapterList = catalog?['chapters'];
      final chapterSubject = <int, int>{};
      if (chapterList is List) {
        for (final raw in chapterList) {
          if (raw is Map &&
              raw['id'] is num &&
              raw['subjectId'] is num) {
            chapterSubject[(raw['id'] as num).toInt()] =
                (raw['subjectId'] as num).toInt();
          }
        }
      }
      for (final raw in topics) {
        if (raw is Map && raw['chapterId'] is num) {
          final subjectId =
              chapterSubject[(raw['chapterId'] as num).toInt()];
          if (subjectId != null) ids.add(subjectId);
        }
      }
    }
    return ids;
  }

  Set<int> _subjectIdsFromCatalogMaster() {
    final catalog = _store.getJson(LocalStore.syncCatalogMasterKey);
    final subjects = catalog?['subjects'];
    if (subjects is! List) return {};
    return subjects
        .whereType<Map>()
        .where((s) => s['id'] is num)
        .map((s) => (s['id'] as num).toInt())
        .toSet();
  }

  /// Deprecated — use [manualSync]. Kept for compatibility.
  Future<void> refreshAll({bool force = true}) => manualSync();

  /// Deprecated — use [runBackgroundSync] or [scheduleBackgroundSync].
  Future<void> fullInitialSync({bool incremental = false, bool force = false}) =>
      runBackgroundSync(fullDownload: !incremental);
}

class _StudyLogAggregate {
  double hours = 0;
  int topics = 0;
  final clientIds = <String?>[];
  String? keepClientId;
  Map<String, dynamic>? payloadTemplate;
}

class CatalogSyncResult {
  final bool hadChanges;
  final Set<int> affectedSubjectIds;
  final String? serverTime;

  const CatalogSyncResult({
    required this.hadChanges,
    required this.affectedSubjectIds,
    this.serverTime,
  });
}
