import 'package:uuid/uuid.dart';

import 'package:flutter/foundation.dart';

import '../local/local_store.dart';
import '../../data/repositories/sync_repository.dart';

/// Pending local changes — uploaded only when user taps SYNC.
class OfflineQueueService {
  OfflineQueueService({
    required LocalStore store,
    required SyncRepository syncRepository,
  })  : _store = store,
        _syncRepository = syncRepository;

  final LocalStore _store;
  final SyncRepository _syncRepository;
  final _uuid = const Uuid();

  /// Notifies UI (banner, sync badge) when pending count changes.
  final ValueNotifier<int> pendingCountListenable = ValueNotifier(0);

  void _refreshPendingCount() {
    pendingCountListenable.value = pendingCount;
  }

  /// Call after sync completes so banner/badge update even if queue unchanged.
  void refreshPendingCount() => _refreshPendingCount();

  List<Map<String, dynamic>> _readQueue() {
    final list = _store.getJsonList(LocalStore.offlineQueueKey);
    if (list == null) return [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> _writeQueue(List<Map<String, dynamic>> items) async {
    await _store.putJson(LocalStore.offlineQueueKey, items);
    _refreshPendingCount();
  }

  /// Enqueue a pending sync item (pending_sync table equivalent in Hive).
  Future<void> enqueue({
    required String entityType,
    required String entityId,
    required String action,
    required Map<String, dynamic> payload,
  }) async {
    final queue = _readQueue();
    queue.add({
      'clientId': _uuid.v4(),
      'entityType': entityType,
      'entityId': entityId,
      'action': action,
      'type': _pushTypeForAction(action),
      'payload': payload,
      'createdAt': DateTime.now().toIso8601String(),
      'syncStatus': 'pending',
    });
    await _writeQueue(queue);
  }

  /// Legacy enqueue by type only (backward compatible).
  Future<void> enqueueLegacy({
    required String type,
    required Map<String, dynamic> payload,
  }) async {
    await enqueue(
      entityType: type,
      entityId: payload['topicId']?.toString() ?? _uuid.v4(),
      action: type,
      payload: payload,
    );
  }

  String _pushTypeForAction(String action) => switch (action) {
        'COMPLETE_TOPIC' || 'ADD_STUDY_HOURS' || 'TOPIC_PROGRESS' =>
          'TOPIC_PROGRESS',
        'LOG_STUDY_HOURS' || 'LOG_STUDY' => 'LOG_STUDY',
        'STUDY_HOURS' => 'STUDY_HOURS',
        _ => action,
      };

  int get pendingCount =>
      _readQueue().where((e) => e['syncStatus'] != 'synced').length;

  List<Map<String, dynamic>> get pendingItems => _readQueue();

  bool _isHandledElsewhere(Map<String, dynamic> item) {
    final action = item['action'] as String?;
    final type = item['type'] as String? ?? action;
    return action == 'SUBMIT_TEST' ||
        action == 'SET_ACTIVE_EXAM' ||
        action == 'COMPLETE_TOPIC' ||
        action == 'ADD_STUDY_HOURS' ||
        action == 'LOG_STUDY_HOURS' ||
        action == 'STUDY_HOURS' ||
        type == 'TOPIC_PROGRESS' ||
        type == 'LOG_STUDY' ||
        type == 'STUDY_HOURS';
  }

  /// Push remaining queue types (e.g. STUDY_HOURS) one item at a time.
  Future<bool> flush({bool force = false}) async {
    final queue = _readQueue();
    if (queue.isEmpty) return true;

    final remaining = <Map<String, dynamic>>[];
    var anyFailed = false;

    for (final item in queue) {
      if (_isHandledElsewhere(item)) {
        remaining.add(item);
        continue;
      }
      if (item['syncStatus'] == 'synced') continue;

      final pushItem = {
        'clientId': item['clientId'],
        'type': item['type'] ?? item['action'],
        'payload': item['payload'],
        'createdAt': item['createdAt'],
      };

      try {
        await _syncRepository.pushChanges([pushItem]);
      } catch (_) {
        anyFailed = true;
        remaining.add(item);
        if (!force) continue;
      }
    }

    await _writeQueue(remaining);
    return !anyFailed;
  }

  Future<void> removeByClientId(String clientId) async {
    final queue = _readQueue()
      ..removeWhere((e) => e['clientId'] == clientId);
    await _writeQueue(queue);
  }

  /// Drop active-exam queue rows already reflected in cached profile.
  Future<void> discardResolvedActiveExamItems() async {
    final profile = _store.getJson(LocalStore.userProfileKey);
    final activeId = (profile?['activeUserExamId'] as num?)?.toInt();
    if (activeId == null) return;

    final queue = _readQueue();
    final before = queue.length;
    queue.removeWhere((e) {
      if (e['action'] != 'SET_ACTIVE_EXAM') return false;
      final queuedId = (e['payload']?['userExamId'] as num?)?.toInt();
      return queuedId == activeId;
    });
    if (queue.length != before) {
      await _writeQueue(queue);
    }
  }

  Future<void> markSynced(String clientId) async {
    final queue = _readQueue();
    for (final item in queue) {
      if (item['clientId'] == clientId) {
        item['syncStatus'] = 'synced';
      }
    }
    await _writeQueue(queue.where((e) => e['syncStatus'] != 'synced').toList());
  }
}
