import 'dart:async';

import 'package:logger/logger.dart';

import '../local/local_store.dart';
import '../network/connectivity_helper.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../data/repositories/mock_test_repository.dart';
import '../../data/repositories/progress_repository.dart';
import '../../data/repositories/sync_repository.dart';
import 'offline_queue_service.dart';
import 'sync_progress.dart';

enum SyncStatus { idle, syncing, success, failed, offline }

/// Manual-sync-only orchestrator. No automatic background sync.
class SyncService {
  SyncService({
    required LocalStore store,
    required SyncRepository syncRepository,
    required OfflineQueueService offlineQueue,
    required DashboardRepository dashboardRepository,
    required ProgressRepository progressRepository,
    required MockTestRepository mockTestRepository,
    required Logger logger,
  })  : _store = store,
        _syncRepository = syncRepository,
        _offlineQueue = offlineQueue,
        _dashboardRepository = dashboardRepository,
        _progressRepository = progressRepository,
        _mockTestRepository = mockTestRepository,
        _logger = logger;

  final LocalStore _store;
  final SyncRepository _syncRepository;
  final OfflineQueueService _offlineQueue;
  final DashboardRepository _dashboardRepository;
  final ProgressRepository _progressRepository;
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

    try {
      await _uploadPending((p) {});
      await _downloadAll(
        onProgress: (_) {},
        incremental: true,
      );
      _setStatus(SyncStatus.success);
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

  Future<void> _uploadPending(void Function(SyncProgress) onProgress) async {
    _emit(SyncStep.uploading, onProgress);

    for (final item in _offlineQueue.pendingItems) {
      if (item['action'] == 'SUBMIT_TEST') {
        try {
          await _mockTestRepository.flushQueuedSubmit(item);
          await _offlineQueue.removeByClientId(item['clientId'] as String);
        } catch (e, st) {
          _logger.w('Submit test flush failed', error: e, stackTrace: st);
        }
      }
    }

    await _offlineQueue.flush();
  }

  Future<void> _downloadAll({
    required void Function(SyncProgress progress) onProgress,
    required bool incremental,
  }) async {
    _emit(SyncStep.preparing, onProgress);

    _emit(SyncStep.userData, onProgress);
    try {
      await syncBundle(incremental: incremental);
    } catch (e, st) {
      _logger.w('Bundle sync failed, using legacy APIs', error: e, stackTrace: st);
      await syncLegacyFallback();
    }

    final exams = await _dashboardRepository.resolveMyExamsFromCache();
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
      final subjects = await _dashboardRepository.getVisibleSubjectsByExam(
        exam.examId,
        forceRemote: true,
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
          await _progressRepository.getSubjectDetail(
            subject.id,
            forceRemote: true,
          );
        } catch (e, st) {
          _logger.w('Subject ${subject.id} download skipped',
              error: e, stackTrace: st);
        }
      }
    }

    _emit(SyncStep.topics, onProgress, current: subjectCount, total: subjectCount);

    await syncCatalog(incremental: incremental);

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
      } catch (e, st) {
        _logger.w('Mock test sync skipped $topicId', error: e, stackTrace: st);
      }
    }

    _emit(SyncStep.progress, onProgress);
    try {
      await _mockTestRepository.getPerformance(forceRemote: true);
    } catch (_) {}
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
        final detail =
            await _progressRepository.getSubjectDetailCached(subject.id);
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

  Future<void> syncBundle({bool incremental = false}) async {
    final since = incremental ? lastBundleSync : null;
    final data = await _syncRepository.syncBundle(since: since);

    final dashboard = data['dashboard'];
    if (dashboard is Map<String, dynamic>) {
      await _store.putJson(LocalStore.dashboardKey, dashboard);
      _dashboardRepository.cacheEmbeddedDashboardProgress(dashboard);
      final user = dashboard['user'];
      if (user != null) {
        await _store.putJson(LocalStore.userProfileKey, user);
      }
    }

    final myExams = data['myExams'];
    if (myExams is List) {
      await _store.putJson(LocalStore.myExamsKey, myExams);
    }

    final progressMap = data['subjectProgressByExamId'];
    if (progressMap is Map) {
      for (final entry in progressMap.entries) {
        final examId = int.tryParse(entry.key.toString());
        if (examId == null) continue;
        await _store.putJson(
          _store.subjectProgressKey(examId),
          entry.value as List<dynamic>,
        );
      }
    }

    final serverTime = data['serverTime'] as String?;
    if (serverTime != null) {
      await _store.putString(LocalStore.syncBundleAtKey, serverTime);
    }
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
  }

  /// Deprecated — use [manualSync]. Kept for compatibility.
  Future<void> refreshAll({bool force = true}) => manualSync();

  /// Deprecated — no automatic sync.
  Future<void> fullInitialSync({bool incremental = false, bool force = false}) =>
      manualSync();
}
