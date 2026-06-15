import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:logger/logger.dart';

import '../local/api_call_tracker.dart';
import '../local/local_store.dart';
import '../network/connectivity_helper.dart';
import '../../data/models/subject_progress_model.dart';
import '../../data/models/subject_model.dart';
import '../../data/models/user_exam_model.dart';
import '../../data/repositories/auth_repository.dart';
import '../../core/sync/progress_rebuild_service.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../data/repositories/daily_progress_reminder_repository.dart';
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
    required DailyProgressReminderRepository dailyProgressReminderRepository,
    required ProgressRebuildService progressRebuildService,
    required MockTestRepository mockTestRepository,
    required Logger logger,
  })  : _store = store,
        _syncRepository = syncRepository,
        _offlineQueue = offlineQueue,
        _authRepository = authRepository,
        _dashboardRepository = dashboardRepository,
        _progressRepository = progressRepository,
        _dailyProgressReminderRepository = dailyProgressReminderRepository,
        _progressRebuildService = progressRebuildService,
        _mockTestRepository = mockTestRepository,
        _logger = logger;

  final LocalStore _store;
  final SyncRepository _syncRepository;
  final OfflineQueueService _offlineQueue;
  final AuthRepository _authRepository;
  final DashboardRepository _dashboardRepository;
  final ProgressRepository _progressRepository;
  final DailyProgressReminderRepository _dailyProgressReminderRepository;
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
      {int current = 0,
      int total = 0,
      String? detail,
      List<SyncProgressItem>? steps}) {
    onProgress(SyncProgress(
      step: step,
      current: current,
      total: total,
      detail: detail,
      steps: steps,
    ));
  }

  void _emitStepProgress(
    void Function(SyncProgress) onProgress,
    List<SyncProgressItem> template,
    String stepId, {
    SyncStep step = SyncStep.preparing,
    String? detail,
    bool complete = false,
  }) {
    final progress = complete
        ? SyncProgress.withCompletedSteps(
            template: template,
            throughId: stepId,
            step: step,
            detail: detail,
          )
        : SyncProgress.withActiveStep(
            template: template,
            activeId: stepId,
            step: step,
            detail: detail,
          );
    onProgress(progress);
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

    if (_activeSync != null) {
      await _activeSync!.future;
    }
    final completer = Completer<void>();
    _activeSync = completer;

    ApiCallTracker.instance.reset();
    final totalSw = Stopwatch()..start();
    _logger.i(
      '[Download] ===== enrollment download started '
      '(userExamId=$userExamId) =====',
    );

    try {
      var stepItems = SyncProgress.enrollmentTemplate();
      _emitStepProgress(
        onProgress,
        stepItems,
        'enrollments',
        step: SyncStep.preparing,
      );
      stepItems = SyncProgress.withActiveStep(
        template: stepItems,
        activeId: 'enrollments',
        step: SyncStep.preparing,
      ).steps!;

      final targets = await _timedDownloadStep(
        'resolve enrollment targets',
        () => _resolveEnrollmentDownloadTargets(userExamId),
      );
      if (targets.isEmpty) {
        throw StateError(
          'Topics could not be downloaded. Check your subject selections and try again.',
        );
      }
      _emitStepProgress(
        onProgress,
        stepItems,
        'enrollments',
        step: SyncStep.preparing,
        detail: targets.map((e) => e.examName).join(', '),
        complete: true,
      );
      stepItems = SyncProgress.withCompletedSteps(
        template: stepItems,
        throughId: 'enrollments',
        detail: targets.map((e) => e.examName).join(', '),
      ).steps!;
      _logger.i(
        '[Download] targets: ${targets.map((e) => 'userExam=${e.id}/exam=${e.examId}').join(', ')}',
      );

      final examIds = targets.map((e) => e.examId).toSet().toList();

      _emitStepProgress(
        onProgress,
        stepItems,
        'bundle',
        step: SyncStep.bundle,
        detail: 'Profile, exams & progress',
      );
      stepItems = SyncProgress.withActiveStep(
        template: stepItems,
        activeId: 'bundle',
        step: SyncStep.bundle,
        detail: 'Profile, exams & progress',
      ).steps!;
      await _timedDownloadStep(
        'GET /sync/bundle (full)',
        () => syncBundle(incremental: false),
      );
      _emitStepProgress(
        onProgress,
        stepItems,
        'bundle',
        step: SyncStep.bundle,
        complete: true,
      );
      stepItems = SyncProgress.withCompletedSteps(
        template: stepItems,
        throughId: 'bundle',
      ).steps!;

      _emitStepProgress(
        onProgress,
        stepItems,
        'catalog',
        step: SyncStep.catalog,
        detail: '${examIds.length} exam(s)',
      );
      stepItems = SyncProgress.withActiveStep(
        template: stepItems,
        activeId: 'catalog',
        step: SyncStep.catalog,
        detail: '${examIds.length} exam(s)',
      ).steps!;
      final catalog = await _timedDownloadStep(
        'GET /sync/catalog?examIds=$examIds',
        () => syncCatalog(incremental: false, examIds: examIds),
      );
      final catalogSubjects = catalog.affectedSubjectIds.length;
      _emitStepProgress(
        onProgress,
        stepItems,
        'catalog',
        step: SyncStep.catalog,
        detail: '$catalogSubjects subject(s) in catalog',
        complete: true,
      );
      stepItems = SyncProgress.withCompletedSteps(
        template: stepItems,
        throughId: 'catalog',
        detail: '$catalogSubjects subject(s) in catalog',
      ).steps!;

      var totalSubjects = 0;
      var totalTopics = 0;

      _emitStepProgress(
        onProgress,
        stepItems,
        'syllabus',
        step: SyncStep.materializing,
        detail: 'Preparing ${targets.length} exam(s)',
      );
      stepItems = SyncProgress.withActiveStep(
        template: stepItems,
        activeId: 'syllabus',
        step: SyncStep.materializing,
        detail: 'Preparing ${targets.length} exam(s)',
      ).steps!;

      for (final exam in targets) {
        _emitStepProgress(
          onProgress,
          stepItems,
          'syllabus',
          step: SyncStep.materializing,
          detail: '${exam.examName} — loading subjects',
        );
        stepItems = SyncProgress.withActiveStep(
          template: stepItems,
          activeId: 'syllabus',
          step: SyncStep.materializing,
          detail: '${exam.examName} — loading subjects',
        ).steps!;

        final subjects = await _timedDownloadStep(
          'resolve subjects (examId=${exam.examId})',
          () => _resolveSubjectsForEnrollment(exam.examId),
        );
        if (subjects.isEmpty) {
          _logger.w(
            'Enrollment download: no subjects resolved for exam ${exam.examId} '
            '(userExam ${exam.id})',
          );
          continue;
        }

        final subjectIds = subjects.map((s) => s.id).toList();
        await _timedDownloadStep(
          'materialize catalog locally (${subjectIds.length} subjects, userExam=${exam.id})',
          () => _progressRepository.materializeSubjectDetailsFromCatalog(
            userExamId: exam.id,
            subjectIds: subjectIds,
          ),
        );

        final touched = catalog.affectedSubjectIds
            .where((id) => subjectIds.contains(id))
            .toList();
        if (touched.isNotEmpty) {
          await _timedDownloadStep(
            'refresh subject caches from catalog (${touched.length} subjects)',
            () => _progressRepository.refreshSubjectDetailsFromCatalog(
              userExamId: exam.id,
              subjectIds: touched,
            ),
          );
        }

        totalSubjects += subjects.length;
        var topicCount = _progressRepository.countCachedTopics(
          userExamId: exam.id,
          subjectIds: subjectIds,
        );
        if (topicCount == 0 && subjects.isNotEmpty) {
          _logger.w(
            '[Download] catalog materialization yielded 0 topics — '
            'fetching ${subjects.length} subject(s) via GET /progress/subject/{id}',
          );
          for (final subject in subjects) {
            await _timedDownloadStep(
              'GET /progress/subject/${subject.id} (userExam=${exam.id})',
              () => _progressRepository.getSubjectDetail(
                subject.id,
                userExamId: exam.id,
                forceRemote: true,
              ),
            );
          }
          topicCount = _progressRepository.countCachedTopics(
            userExamId: exam.id,
            subjectIds: subjectIds,
          );
        }
        totalTopics += topicCount;
        _emitStepProgress(
          onProgress,
          stepItems,
          'syllabus',
          step: SyncStep.materializing,
          detail:
              '${exam.examName} — ${subjects.length} subjects, $topicCount topics',
        );
        stepItems = SyncProgress.withActiveStep(
          template: stepItems,
          activeId: 'syllabus',
          step: SyncStep.materializing,
          detail:
              '${exam.examName} — ${subjects.length} subjects, $topicCount topics',
        ).steps!;
        _logger.i(
          'Enrollment download: exam ${exam.examName} (userExam ${exam.id}) — '
          '${subjects.length} subjects, $topicCount topics cached',
        );
      }

      if (totalSubjects == 0 || totalTopics == 0) {
        throw StateError(
          'Topics could not be downloaded. Check your subject selections and try again.',
        );
      }

      _emitStepProgress(
        onProgress,
        stepItems,
        'syllabus',
        step: SyncStep.materializing,
        detail: '$totalSubjects subjects, $totalTopics topics saved',
        complete: true,
      );
      stepItems = SyncProgress.withCompletedSteps(
        template: stepItems,
        throughId: 'syllabus',
        detail: '$totalSubjects subjects, $totalTopics topics saved',
      ).steps!;

      _emitStepProgress(
        onProgress,
        stepItems,
        'progress',
        step: SyncStep.progress,
        detail: 'Updating topic completion',
      );
      stepItems = SyncProgress.withActiveStep(
        template: stepItems,
        activeId: 'progress',
        step: SyncStep.progress,
        detail: 'Updating topic completion',
      ).steps!;
      await _timedDownloadStep(
        'apply topic progress rows',
        () => _progressRepository.applyTopicProgressForEnrollments(
          targets.map((e) => e.id).toSet(),
        ),
      );
      _emitStepProgress(
        onProgress,
        stepItems,
        'progress',
        step: SyncStep.progress,
        complete: true,
      );
      stepItems = SyncProgress.withCompletedSteps(
        template: stepItems,
        throughId: 'progress',
      ).steps!;

      _emitStepProgress(
        onProgress,
        stepItems,
        'finalize',
        step: SyncStep.finalizing,
        detail: 'Building study views',
      );
      stepItems = SyncProgress.withActiveStep(
        template: stepItems,
        activeId: 'finalize',
        step: SyncStep.finalizing,
        detail: 'Building study views',
      ).steps!;
      await _timedDownloadStep(
        'rebuild progress views',
        () => _progressRebuildService.rebuildExams(
          targets.map((e) => e.examId),
        ),
      );
      if (catalog.serverTime != null) {
        await _persistLastSyncTime(catalog.serverTime ?? _lastBundleServerTime);
      }
      _emitStepProgress(
        onProgress,
        stepItems,
        'finalize',
        step: SyncStep.complete,
        detail: 'Ready for offline study',
        complete: true,
      );
      _logger.i(
        'Enrollment download complete — $totalSubjects subjects, $totalTopics topics',
      );
      _emit(
        SyncStep.complete,
        onProgress,
        detail: '$totalSubjects subjects, $totalTopics topics',
        steps: SyncProgress.withCompletedSteps(
          template: stepItems,
          throughId: 'finalize',
          step: SyncStep.complete,
          detail: 'Ready for offline study',
        ).steps,
      );
    } finally {
      totalSw.stop();
      _logger.i(
        '[Download] ===== enrollment download finished in '
        '${totalSw.elapsedMilliseconds}ms =====',
      );
      ApiCallTracker.instance.logSummary(_logger);
      completer.complete();
      if (identical(_activeSync, completer)) {
        _activeSync = null;
      }
    }
  }

  Future<List<UserExamModel>> _resolveEnrollmentDownloadTargets(
      int? userExamId) async {
    var exams = await _dashboardRepository.resolveMyExamsFromCache();
    if (exams.isEmpty) {
      exams = await _dashboardRepository.getMyExams(forceRemote: true);
    }

    Iterable<UserExamModel> targets = userExamId != null
        ? exams.where((e) => e.id == userExamId)
        : exams.where((e) => e.isActive);

    if (targets.isEmpty && userExamId != null) {
      final profile = _store.getJson(LocalStore.userProfileKey);
      final rawExams = profile?['userExams'];
      if (rawExams is List) {
        for (final raw in rawExams) {
          if (raw is! Map<String, dynamic>) continue;
          if ((raw['id'] as num?)?.toInt() == userExamId) {
            return [UserExamModel.fromJson(raw)];
          }
        }
      }
      final activeId = (profile?['activeUserExamId'] as num?)?.toInt();
      if (activeId == userExamId) {
        final selectedExamId = (profile?['selectedExamId'] as num?)?.toInt();
        if (selectedExamId != null) {
          return [
            UserExamModel(
              id: userExamId,
              examId: selectedExamId,
              examName: profile?['selectedExamName'] as String? ?? 'Exam',
              isActive: true,
            ),
          ];
        }
      }
    }

    if (targets.isEmpty) {
      targets = exams.where((e) => e.isActive);
    }
    if (targets.isEmpty && exams.isNotEmpty) {
      targets = [exams.first];
    }
    return targets.toList(growable: false);
  }

  /// Visible subjects for a new enrollment — always fetch from server so optional
  /// selections saved during enroll are reflected before catalog materialization.
  Future<List<SubjectModel>> _resolveSubjectsForEnrollment(int examId) async {
    return _dashboardRepository.resolveSubjectsForExam(
      examId,
      forceRemote: true,
    );
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
    await _coalesceTopicProgressToBulk();
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
            action == 'BULK_TOPIC_PROGRESS' ||
            type == 'TOPIC_PROGRESS') {
          await _progressRepository.flushQueuedTopicProgress(item);
        } else if (action == 'LOG_STUDY_HOURS' || type == 'LOG_STUDY') {
          await _progressRepository.flushQueuedStudyLog(item);
        } else if (action == 'NO_STUDY_DAY') {
          await _dailyProgressReminderRepository.flushQueuedNoStudyDay(item);
        } else if (action == 'DAILY_PROGRESS_REMINDER') {
          await _dailyProgressReminderRepository.flushQueuedPreference(item);
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
        action == 'BULK_TOPIC_PROGRESS' ||
        type == 'TOPIC_PROGRESS';
  }

  /// Merge pending per-topic rows into one bulk upload per enrollment.
  Future<void> _coalesceTopicProgressToBulk() async {
    final pending =
        List<Map<String, dynamic>>.from(_offlineQueue.processableItems);
    final mergedByExam = <int, Map<int, _TopicProgressMerge>>{};
    final topicItemClientIds = <String>[];

    for (final item in pending) {
      if (!_isTopicProgressItem(item)) continue;
      final clientId = item['clientId'] as String?;
      if (clientId != null) topicItemClientIds.add(clientId);

      final payload = item['payload'];
      if (payload is! Map<String, dynamic>) continue;
      final userExamId = (payload['userExamId'] as num?)?.toInt();
      if (userExamId == null) continue;

      final action = item['action'] as String?;
      if (action == 'BULK_TOPIC_PROGRESS') {
        final topics = payload['topics'];
        if (topics is! List) continue;
        for (final raw in topics) {
          if (raw is! Map<String, dynamic>) continue;
          _mergeTopicProgressPayload(mergedByExam, userExamId, raw);
        }
        continue;
      }

      _mergeTopicProgressPayload(mergedByExam, userExamId, payload);
    }

    if (mergedByExam.isEmpty || topicItemClientIds.length <= 1) return;

    var shouldReplace = false;
    for (final topics in mergedByExam.values) {
      if (topics.length >= 2) {
        shouldReplace = true;
        break;
      }
    }
    if (!shouldReplace) return;

    for (final clientId in topicItemClientIds) {
      await _offlineQueue.removeByClientId(clientId);
    }

    for (final entry in mergedByExam.entries) {
      final topics = entry.value.entries
          .map((e) => e.value.toPayload(e.key))
          .toList(growable: false);
      await _progressRepository.enqueueBulkTopicProgress(
        userExamId: entry.key,
        topics: topics,
      );
    }
  }

  void _mergeTopicProgressPayload(
    Map<int, Map<int, _TopicProgressMerge>> mergedByExam,
    int userExamId,
    Map<String, dynamic> payload,
  ) {
    final topicId = (payload['topicId'] as num?)?.toInt();
    if (topicId == null) return;

    final byTopic = mergedByExam.putIfAbsent(userExamId, () => {});
    final merge = byTopic.putIfAbsent(topicId, _TopicProgressMerge.new);
    merge.apply(
      isCompleted: payload['isCompleted'] as bool? ?? false,
      actualHours: (payload['actualHours'] as num?)?.toDouble() ?? 0.0,
    );
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
        final touched =
            catalog.affectedSubjectIds.where(subjectIds.contains).toList();
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
    ApiCallTracker.instance.reset();
    final totalSw = Stopwatch()..start();
    _logger.i('[Download] ===== full download started =====');

    var stepItems = SyncProgress.fullDownloadTemplate();
    _emitStepProgress(onProgress, stepItems, 'profile',
        step: SyncStep.userData);
    stepItems = SyncProgress.withActiveStep(
      template: stepItems,
      activeId: 'profile',
      step: SyncStep.userData,
    ).steps!;
    final stats = SyncDownloadStats();

    try {
      await _authRepository.getMe();
    } catch (e, st) {
      _logger.w('Profile refresh skipped before sync',
          error: e, stackTrace: st);
    }
    _emitStepProgress(
      onProgress,
      stepItems,
      'profile',
      step: SyncStep.userData,
      complete: true,
    );
    stepItems = SyncProgress.withCompletedSteps(
      template: stepItems,
      throughId: 'profile',
    ).steps!;

    _emitStepProgress(
      onProgress,
      stepItems,
      'bundle',
      step: SyncStep.bundle,
      detail: 'Exams, dashboard & progress',
    );
    stepItems = SyncProgress.withActiveStep(
      template: stepItems,
      activeId: 'bundle',
      step: SyncStep.bundle,
      detail: 'Exams, dashboard & progress',
    ).steps!;
    try {
      stats.studyProgressRows = await syncBundle(incremental: false);
    } catch (e, st) {
      _logger.w('Bundle sync failed, using legacy APIs',
          error: e, stackTrace: st);
      await syncLegacyFallback();
    }
    _emitStepProgress(
      onProgress,
      stepItems,
      'bundle',
      step: SyncStep.bundle,
      complete: true,
    );
    stepItems = SyncProgress.withCompletedSteps(
      template: stepItems,
      throughId: 'bundle',
    ).steps!;

    final exams = await _dashboardRepository.resolveMyExamsFromCache();
    stats.exams = exams.length;
    var subjectCount = 0;
    for (final exam in exams) {
      subjectCount += (await _dashboardRepository.getVisibleSubjectsByExam(
        exam.examId,
        forceRemote: false,
      ))
          .length;
    }
    if (subjectCount == 0) subjectCount = 1;

    var subjectIndex = 0;
    _emitStepProgress(
      onProgress,
      stepItems,
      'subjects',
      step: SyncStep.subjects,
      detail: subjectCount > 0 ? '0 / $subjectCount subjects' : null,
    );
    stepItems = SyncProgress.withActiveStep(
      template: stepItems,
      activeId: 'subjects',
      step: SyncStep.subjects,
      detail: subjectCount > 0 ? '0 / $subjectCount subjects' : null,
    ).steps!;

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
        final subjectDetail = '$subjectIndex / $subjectCount — ${subject.name}';
        _emitStepProgress(
          onProgress,
          stepItems,
          'subjects',
          step: SyncStep.chapters,
          detail: subjectDetail,
        );
        stepItems = SyncProgress.withActiveStep(
          template: stepItems,
          activeId: 'subjects',
          step: SyncStep.chapters,
          detail: subjectDetail,
        ).steps!;
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

    _emitStepProgress(
      onProgress,
      stepItems,
      'subjects',
      step: SyncStep.topics,
      detail: '${stats.subjects} subjects, ${stats.topics} topics',
      complete: true,
    );
    stepItems = SyncProgress.withCompletedSteps(
      template: stepItems,
      throughId: 'subjects',
      detail: '${stats.subjects} subjects, ${stats.topics} topics',
    ).steps!;

    _emitStepProgress(
      onProgress,
      stepItems,
      'catalog',
      step: SyncStep.catalog,
    );
    stepItems = SyncProgress.withActiveStep(
      template: stepItems,
      activeId: 'catalog',
      step: SyncStep.catalog,
    ).steps!;
    await syncCatalog(incremental: false);
    _emitStepProgress(
      onProgress,
      stepItems,
      'catalog',
      step: SyncStep.catalog,
      complete: true,
    );
    stepItems = SyncProgress.withCompletedSteps(
      template: stepItems,
      throughId: 'catalog',
    ).steps!;

    await _progressRepository.applyTopicProgressTableToSubjectDetails();
    stats.dailyStudyLogs = await _progressRepository.downloadWeeklyStudyLogs();

    await _mockTestRepository.clearOfflineCache();
    final mockTestTopicIds = _resolveMockTestTopicIds();
    if (mockTestTopicIds.isEmpty) {
      stepItems = stepItems
          .map((item) => item.id == 'mocktests'
              ? item.copyWith(
                  status: SyncProgressItemStatus.done,
                  detail: 'No mock tests to download',
                )
              : item)
          .toList(growable: false);
      _emit(
        SyncStep.mockTests,
        onProgress,
        detail: 'No mock tests to download',
        steps: stepItems,
      );
    } else {
      _emitStepProgress(
        onProgress,
        stepItems,
        'mocktests',
        step: SyncStep.mockTests,
        detail: '0 / ${mockTestTopicIds.length} topics',
      );
      stepItems = SyncProgress.withActiveStep(
        template: stepItems,
        activeId: 'mocktests',
        step: SyncStep.mockTests,
        detail: '0 / ${mockTestTopicIds.length} topics',
      ).steps!;

      var topicIndex = 0;
      for (final topicId in mockTestTopicIds) {
        topicIndex++;
        final mockDetail = '$topicIndex / ${mockTestTopicIds.length} topics';
        _emitStepProgress(
          onProgress,
          stepItems,
          'mocktests',
          step: SyncStep.mockTests,
          detail: mockDetail,
        );
        stepItems = SyncProgress.withActiveStep(
          template: stepItems,
          activeId: 'mocktests',
          step: SyncStep.mockTests,
          detail: mockDetail,
        ).steps!;
        try {
          final questionCount =
              await _mockTestRepository.syncTopicForOffline(topicId);
          if (questionCount > 0) {
            stats.mockTests++;
            stats.questions += questionCount;
          }
        } catch (e, st) {
          _logger.w('Mock test sync skipped $topicId',
              error: e, stackTrace: st);
        }
      }
      _emitStepProgress(
        onProgress,
        stepItems,
        'mocktests',
        step: SyncStep.mockTests,
        detail: '${stats.mockTests} mock tests cached',
        complete: true,
      );
      stepItems = SyncProgress.withCompletedSteps(
        template: stepItems,
        throughId: 'mocktests',
        detail: '${stats.mockTests} mock tests cached',
      ).steps!;
    }

    _emitStepProgress(
      onProgress,
      stepItems,
      'finalize',
      step: SyncStep.finalizing,
      detail: 'Building offline views',
    );
    stepItems = SyncProgress.withActiveStep(
      template: stepItems,
      activeId: 'finalize',
      step: SyncStep.finalizing,
      detail: 'Building offline views',
    ).steps!;
    try {
      await _mockTestRepository.getPerformance(forceRemote: true);
    } catch (_) {}
    await _progressRebuildService.rebuildAll();
    await _persistLastSyncTime(null);
    _emitStepProgress(
      onProgress,
      stepItems,
      'finalize',
      step: SyncStep.complete,
      detail: 'Ready for offline study',
      complete: true,
    );
    stats.log(_logger);
    totalSw.stop();
    _logger.i(
      '[Download] ===== full download finished in '
      '${totalSw.elapsedMilliseconds}ms =====',
    );
    ApiCallTracker.instance.logSummary(_logger);
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
    _logBundlePayload(data, incremental: incremental);

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
      final base = existing ??
          <String, dynamic>{
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
                (row) =>
                    SubjectProgressModel.fromJson(row).toSubjectModel(examId),
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
    _logCatalogPayload(
      data,
      label: scopedExamIds.isEmpty ? 'full' : 'examIds=$scopedExamIds',
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
      var subjects = await _dashboardRepository.getVisibleSubjectsByExam(
        exam.examId,
        forceRemote: false,
      );
      if (subjects.isEmpty) {
        subjects = await _dashboardRepository.resolveSubjectsForExam(
          exam.examId,
          forceRemote: true,
        );
      }
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
    final parsed = serverTime != null ? DateTime.tryParse(serverTime) : null;
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
          if (raw is Map && raw['id'] is num && raw['subjectId'] is num) {
            chapterSubject[(raw['id'] as num).toInt()] =
                (raw['subjectId'] as num).toInt();
          }
        }
      }
      for (final raw in topics) {
        if (raw is Map && raw['chapterId'] is num) {
          final subjectId = chapterSubject[(raw['chapterId'] as num).toInt()];
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
  Future<void> fullInitialSync(
          {bool incremental = false, bool force = false}) =>
      runBackgroundSync(fullDownload: !incremental);

  Future<T> _timedDownloadStep<T>(
    String step,
    Future<T> Function() action,
  ) async {
    final sw = Stopwatch()..start();
    _logger.i('[Download] → $step');
    try {
      return await action();
    } catch (e, st) {
      _logger.e(
        '[Download] ✗ $step failed after ${sw.elapsedMilliseconds}ms',
        error: e,
        stackTrace: st,
      );
      rethrow;
    } finally {
      sw.stop();
      _logger.i('[Download] ← $step (${sw.elapsedMilliseconds}ms)');
    }
  }

  void _logCatalogPayload(
    Map<String, dynamic> data, {
    String? label,
  }) {
    final exams = (data['exams'] as List?)?.length ?? 0;
    final subjects = (data['subjects'] as List?)?.length ?? 0;
    final chapters = (data['chapters'] as List?)?.length ?? 0;
    final topics = (data['topics'] as List?)?.length ?? 0;
    _logger.i(
      '[Download] catalog payload${label != null ? ' ($label)' : ''}: '
      '$exams exams, $subjects subjects, $chapters chapters, $topics topics',
    );
  }

  void _logBundlePayload(
    Map<String, dynamic> data, {
    required bool incremental,
  }) {
    final myExams = (data['myExams'] as List?)?.length;
    final changedProgress = (data['changedProgress'] as List?)?.length ?? 0;
    final progressByExam =
        (data['subjectProgressByExamId'] as Map?)?.length ?? 0;
    final hasDashboard = data['dashboard'] != null;
    _logger.i(
      '[Download] bundle payload (incremental=$incremental): '
      'dashboard=$hasDashboard, myExams=$myExams, '
      'subjectProgressByExamId=$progressByExam, changedProgress=$changedProgress',
    );
  }
}

class _TopicProgressMerge {
  bool isCompleted = false;
  double actualHours = 0;

  void apply({required bool isCompleted, required double actualHours}) {
    if (isCompleted) this.isCompleted = true;
    if (actualHours > this.actualHours) {
      this.actualHours = actualHours;
    }
  }

  Map<String, dynamic> toPayload(int topicId) => {
        'topicId': topicId,
        'isCompleted': isCompleted,
        'actualHours': actualHours,
      };
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
