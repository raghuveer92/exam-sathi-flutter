import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:logger/logger.dart';

import '../local/local_store.dart';
import '../../data/repositories/sync_repository.dart';
import 'offline_queue_service.dart';

/// Orchestrates full/incremental sync, background refresh, and offline queue flush.
class SyncService {
  SyncService({
    required LocalStore store,
    required SyncRepository syncRepository,
    required OfflineQueueService offlineQueue,
    required Logger logger,
  })  : _store = store,
        _syncRepository = syncRepository,
        _offlineQueue = offlineQueue,
        _logger = logger;

  final LocalStore _store;
  final SyncRepository _syncRepository;
  final OfflineQueueService _offlineQueue;
  final Logger _logger;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _syncing = false;

  void startConnectivityListener() {
    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) {
        unawaited(flushOfflineQueue());
        unawaited(syncBundle(incremental: true));
      }
    });
  }

  Future<void> dispose() async {
    await _connectivitySub?.cancel();
  }

  DateTime? get lastBundleSync {
    final raw = _store.getString(LocalStore.syncBundleAtKey);
    return raw != null ? DateTime.tryParse(raw) : null;
  }

  Future<bool> isOnline() async {
    final results = await Connectivity().checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  Future<void> flushOfflineQueue() => _offlineQueue.flush();

  /// Full sync on first launch; incremental when [incremental] is true.
  Future<void> syncBundle({bool incremental = false, bool force = false}) async {
    if (_syncing && !force) return;
    _syncing = true;
    try {
      if (!await isOnline()) return;
      await _offlineQueue.flush();

      final since = incremental ? lastBundleSync : null;
      final data = await _syncRepository.syncBundle(since: since);

      final dashboard = data['dashboard'];
      if (dashboard != null) {
        await _store.putJson(LocalStore.dashboardKey, dashboard);
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
      _syncing = false;
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

  /// Manual refresh: catalog + bundle + UI sources.
  Future<void> refreshAll() async {
    await syncCatalog(incremental: false);
    await syncBundle(incremental: false, force: true);
  }
}
