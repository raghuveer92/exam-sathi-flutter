import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:logger/logger.dart';

import '../local/local_store.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../data/repositories/mock_test_repository.dart';
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

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _syncing = false;
  SyncStatus _status = SyncStatus.idle;
  String? _lastError;

  SyncStatus get status => _status;
  String? get lastError => _lastError;
  bool get isSyncing => _syncing;

  final _statusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _statusController.stream;

  void startConnectivityListener() {
    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
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

  Future<bool> isOnline() async {
    final results = await Connectivity().checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

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

  /// Login / startup: bundle + visible subjects + subject details + catalog.
  Future<void> fullInitialSync({bool incremental = false}) async {
    if (_syncing) return;
    _syncing = true;
    _lastError = null;
    _setStatus(SyncStatus.syncing);

    try {
      if (!await isOnline()) {
        _setStatus(SyncStatus.offline);
        return;
      }

      await _offlineQueue.flush();
      await syncBundle(incremental: incremental, force: true);
      await syncLearningContent(forceRemote: true);
      await syncCatalog(incremental: incremental);
      _setStatus(SyncStatus.success);
    } catch (e, st) {
      _lastError = e.toString();
      _logger.w('Full sync failed', error: e, stackTrace: st);
      _setStatus(SyncStatus.failed);
    } finally {
      _syncing = false;
    }
  }

  Future<void> syncBundle({bool incremental = false, bool force = false}) async {
    if (_syncing && !force) return;
    final wasSyncing = _syncing;
    _syncing = true;
    try {
      if (!await isOnline()) return;

      final since = incremental ? lastBundleSync : null;
      final data = await _syncRepository.syncBundle(since: since);

      final dashboard = data['dashboard'];
      if (dashboard != null) {
        await _store.putJson(LocalStore.dashboardKey, dashboard);
        final user = (dashboard as Map<String, dynamic>)['user'];
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
    } catch (e, st) {
      _logger.w('Bundle sync failed', error: e, stackTrace: st);
      rethrow;
    } finally {
      if (!wasSyncing) _syncing = false;
    }
  }

  /// Download visible subjects + full subject detail (chapters/topics) per exam.
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
          await _progressRepository.getSubjectDetail(
            subject.id,
            forceRemote: forceRemote,
          );
          for (final topicId in await _topicIdsForSubject(subject.id)) {
            try {
              await _mockTestRepository.getTopicInfo(topicId, forceRemote: forceRemote);
            } catch (_) {}
          }
        }
      } catch (e, st) {
        _logger.w('Content sync failed for exam ${exam.examId}', error: e, stackTrace: st);
      }
    }
  }

  Future<List<int>> _topicIdsForSubject(int subjectId) async {
    final detail = await _progressRepository.getSubjectDetailCached(subjectId);
    if (detail == null) return const [];
    return detail.chapters
        .expand((chapter) => chapter.topics)
        .map((topic) => topic.id)
        .toList();
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

  Future<void> refreshAll() async {
    await fullInitialSync(incremental: false);
  }
}
