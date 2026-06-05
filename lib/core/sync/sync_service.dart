import 'dart:async';

import 'package:logger/logger.dart';

import '../local/local_store.dart';
import '../network/connectivity_helper.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../data/repositories/progress_repository.dart';
import '../../data/repositories/sync_repository.dart';
import 'offline_queue_service.dart';

enum SyncStatus { idle, syncing, success, failed, offline }

/// Central sync manager: bundle, catalog, learning content, offline queue.
class SyncService {
  SyncService({
    required LocalStore store,
    required SyncRepository syncRepository,
    required OfflineQueueService offlineQueue,
    required DashboardRepository dashboardRepository,
    required ProgressRepository progressRepository,
    required Logger logger,
  })  : _store = store,
        _syncRepository = syncRepository,
        _offlineQueue = offlineQueue,
        _dashboardRepository = dashboardRepository,
        _progressRepository = progressRepository,
        _logger = logger;

  final LocalStore _store;
  final SyncRepository _syncRepository;
  final OfflineQueueService _offlineQueue;
  final DashboardRepository _dashboardRepository;
  final ProgressRepository _progressRepository;
  final Logger _logger;

  StreamSubscription? _connectivitySub;
  Completer<void>? _activeSync;
  SyncStatus _status = SyncStatus.idle;
  String? _lastError;

  SyncStatus get status => _status;
  String? get lastError => _lastError;
  bool get isSyncing => _activeSync != null;

  final _statusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _statusController.stream;

  void startConnectivityListener() {
    _connectivitySub?.cancel();
    _connectivitySub = listenForConnectivity((online) {
      if (online) {
        unawaited(fullInitialSync(incremental: true));
      }
    });
  }

  Future<void> dispose() async {
    await _connectivitySub?.cancel();
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

  Future<void> flushOfflineQueue() => _offlineQueue.flush();

  /// Waits for an in-flight sync or starts a new one.
  Future<void> fullInitialSync({bool incremental = false, bool force = false}) async {
    if (_activeSync != null) {
      return _activeSync!.future;
    }
    final completer = Completer<void>();
    _activeSync = completer;
    _lastError = null;
    _setStatus(SyncStatus.syncing);

    try {
      if (!force && !await isOnline()) {
        _setStatus(SyncStatus.offline);
        return;
      }

      await _offlineQueue.flush();

      try {
        await syncBundle(incremental: incremental, force: true);
      } catch (e, st) {
        _logger.w('Bundle sync failed, using legacy APIs', error: e, stackTrace: st);
        await syncLegacyFallback();
      }

      await syncLearningContent(forceRemote: true);
      try {
        await syncCatalog(incremental: incremental);
      } catch (e, st) {
        _logger.w('Catalog sync failed (non-fatal)', error: e, stackTrace: st);
      }
      _setStatus(SyncStatus.success);
    } catch (e, st) {
      _lastError = e.toString();
      _logger.w('Full sync failed', error: e, stackTrace: st);
      _setStatus(SyncStatus.failed);
    } finally {
      completer.complete();
      _activeSync = null;
    }
  }

  /// Fallback when /sync/bundle is unavailable — uses existing REST endpoints.
  Future<void> syncLegacyFallback() async {
    await _dashboardRepository.fetchDashboardFromNetwork();
    final exams = await _dashboardRepository.getMyExams(forceRemote: true);
    for (final exam in exams) {
      await _dashboardRepository.getSubjectProgressByExam(exam.examId, forceRemote: true);
      await _dashboardRepository.getVisibleSubjectsByExam(exam.examId, forceRemote: true);
    }
    await _store.putString(
      LocalStore.syncBundleAtKey,
      DateTime.now().toIso8601String(),
    );
  }

  Future<void> syncBundle({bool incremental = false, bool force = false}) async {
    if (!await isOnline()) return;

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

  Future<void> syncLearningContent({bool forceRemote = false}) async {
    if (!await isOnline()) return;
    final exams = await _dashboardRepository.resolveMyExamsFromCache();
    for (final exam in exams) {
      try {
        final subjects = await _dashboardRepository.getVisibleSubjectsByExam(
          exam.examId,
          forceRemote: forceRemote,
        );
        for (final subject in subjects) {
          try {
            await _progressRepository.getSubjectDetail(
              subject.id,
              forceRemote: forceRemote,
            );
          } catch (e, st) {
            _logger.w('Subject detail sync skipped ${subject.id}', error: e, stackTrace: st);
          }
        }
      } catch (e, st) {
        _logger.w('Content sync failed for exam ${exam.examId}', error: e, stackTrace: st);
      }
    }
  }

  Future<void> syncCatalog({bool incremental = false}) async {
    if (!await isOnline()) return;
    final raw = _store.getString(LocalStore.syncCatalogAtKey);
    final since = incremental && raw != null ? DateTime.tryParse(raw) : null;
    final data = await _syncRepository.syncCatalog(since: since);
    await _store.putJson(LocalStore.syncCatalogMasterKey, data);
    final serverTime = data['serverTime'] as String?;
    if (serverTime != null) {
      await _store.putString(LocalStore.syncCatalogAtKey, serverTime);
    }
  }

  Future<void> refreshAll({bool force = true}) async {
    await fullInitialSync(incremental: false, force: force);
  }
}
