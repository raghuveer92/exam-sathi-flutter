import 'package:uuid/uuid.dart';

import 'package:flutter/foundation.dart';

import '../local/local_store.dart';
import '../../data/repositories/sync_repository.dart';
import 'local_tables.dart';
import 'sync_queue_constants.dart';

/// Persistent sync queue — every local write enqueues here; [SyncService] drains it.
class OfflineQueueService {
  OfflineQueueService({
    required LocalStore store,
    required SyncRepository syncRepository,
  })  : _store = store,
        _syncRepository = syncRepository;

  static const maxRetries = 5;

  final LocalStore _store;
  final SyncRepository _syncRepository;
  final _uuid = const Uuid();

  /// Called after enqueue so [SyncService] can schedule background upload.
  VoidCallback? onQueueChanged;

  /// Notifies UI (sync indicator badge) when pending count changes.
  final ValueNotifier<int> pendingCountListenable = ValueNotifier(0);

  void _refreshPendingCount() {
    pendingCountListenable.value = pendingCount;
  }

  /// Call after sync completes so indicator updates even if queue unchanged.
  void refreshPendingCount() => _refreshPendingCount();

  List<Map<String, dynamic>> _readQueue() {
    final list = _store.getJsonList(LocalStore.offlineQueueKey);
    if (list == null) return [];
    return list
        .map((e) => _normalizeItem(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Map<String, dynamic> _normalizeItem(Map<String, dynamic> item) {
    final legacy = item['syncStatus'] as String?;
    item['status'] ??= switch (legacy) {
      'synced' => SyncQueueStatus.completed,
      'pending' || null => SyncQueueStatus.pending,
      String s => s.toUpperCase(),
    };
    item['operationType'] ??=
        SyncOperationType.forAction(item['action'] as String? ?? '');
    item['payloadJson'] ??= item['payload'];
    item['payload'] ??= item['payloadJson'];
    item['retryCount'] ??= 0;
    item['updatedAt'] ??= item['createdAt'] ?? DateTime.now().toIso8601String();
    return item;
  }

  String _itemStatus(Map<String, dynamic> item) =>
      item['status'] as String? ?? SyncQueueStatus.pending;

  int _itemRetryCount(Map<String, dynamic> item) =>
      (item['retryCount'] as num?)?.toInt() ?? 0;

  bool _isProcessable(Map<String, dynamic> item) {
    final status = _itemStatus(item);
    if (status == SyncQueueStatus.pending) return true;
    if (status == SyncQueueStatus.failed &&
        _itemRetryCount(item) < maxRetries) {
      return true;
    }
    return false;
  }

  Future<void> _writeQueue(List<Map<String, dynamic>> items) async {
    await _store.putJson(LocalStore.offlineQueueKey, items);
    _refreshPendingCount();
  }

  /// Enqueue a pending sync item (sync_queue table equivalent in Hive).
  Future<void> enqueue({
    required String entityType,
    required String entityId,
    required String action,
    required Map<String, dynamic> payload,
  }) async {
    final now = DateTime.now().toIso8601String();
    final queue = _readQueue();
    queue.add({
      'id': _uuid.v4(),
      'clientId': _uuid.v4(),
      'entityType': entityType,
      'entityId': entityId,
      'action': action,
      'operationType': SyncOperationType.forAction(action),
      'type': _pushTypeForAction(action),
      'payload': payload,
      'payloadJson': payload,
      'createdAt': now,
      'updatedAt': now,
      'status': SyncQueueStatus.pending,
      'syncStatus': 'pending',
      'retryCount': 0,
    });
    await _writeQueue(queue);
    onQueueChanged?.call();
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
        _ => action,
      };

  int get pendingCount => _readQueue().where(_isProcessable).length;

  /// Rows waiting to be uploaded (PENDING or retriable FAILED).
  List<Map<String, dynamic>> get processableItems =>
      _readQueue().where(_isProcessable).toList();

  /// All non-completed rows (includes SYNCING during upload).
  List<Map<String, dynamic>> get pendingItems => _readQueue()
      .where((e) => _itemStatus(e) != SyncQueueStatus.completed)
      .toList();

  bool _isHandledElsewhere(Map<String, dynamic> item) {
    final action = item['action'] as String?;
    final type = item['type'] as String? ?? action;
    return action == 'SUBMIT_TEST' ||
        action == 'SET_ACTIVE_EXAM' ||
        action == 'UPDATE_EXAM_DATE' ||
        action == 'COMPLETE_TOPIC' ||
        action == 'ADD_STUDY_HOURS' ||
        action == 'LOG_STUDY_HOURS' ||
        type == 'TOPIC_PROGRESS' ||
        type == 'LOG_STUDY';
  }

  Future<void> updateStatus(String clientId, String status) async {
    final queue = _readQueue();
    for (final item in queue) {
      if (item['clientId'] == clientId) {
        item['status'] = status;
        item['updatedAt'] = DateTime.now().toIso8601String();
        break;
      }
    }
    await _writeQueue(queue);
  }

  Future<int> markFailed(String clientId) async {
    final queue = _readQueue();
    var retries = 0;
    for (final item in queue) {
      if (item['clientId'] == clientId) {
        retries = _itemRetryCount(item) + 1;
        item['retryCount'] = retries;
        item['status'] = retries >= maxRetries
            ? SyncQueueStatus.failed
            : SyncQueueStatus.pending;
        item['updatedAt'] = DateTime.now().toIso8601String();
        break;
      }
    }
    await _writeQueue(queue);
    return retries;
  }

  /// Push remaining queue types one item at a time.
  Future<bool> flush({bool force = false}) async {
    final queue = _readQueue();
    if (queue.isEmpty) return true;

    final remaining = <Map<String, dynamic>>[];
    var anyFailed = false;

    for (final item in queue) {
      if (_isHandledElsewhere(item)) {
        if (_isProcessable(item)) {
          remaining.add(item);
        }
        continue;
      }
      if (_itemStatus(item) == SyncQueueStatus.completed) continue;
      if (!_isProcessable(item) && !force) {
        remaining.add(item);
        continue;
      }

      final clientId = item['clientId'] as String?;
      if (clientId != null) {
        await updateStatus(clientId, SyncQueueStatus.syncing);
      }

      final pushItem = {
        'clientId': item['clientId'],
        'type': item['type'] ?? item['action'],
        'payload': item['payload'] ?? item['payloadJson'],
        'createdAt': item['createdAt'],
      };

      try {
        await _syncRepository.pushChanges([pushItem]);
      } catch (_) {
        anyFailed = true;
        if (clientId != null) {
          await markFailed(clientId);
        }
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

  Future<void> updatePayloadByClientId(
    String clientId,
    Map<String, dynamic> payload,
  ) async {
    final queue = _readQueue();
    for (final item in queue) {
      if (item['clientId'] == clientId) {
        item['payload'] = payload;
        item['payloadJson'] = payload;
        item['updatedAt'] = DateTime.now().toIso8601String();
        break;
      }
    }
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
    await removeByClientId(clientId);
  }

  /// Unstick rows left in SYNCING after a crashed/interrupted sync.
  Future<void> resetStuckSyncingItems() async {
    final queue = _readQueue();
    var changed = false;
    for (final item in queue) {
      if (_itemStatus(item) == SyncQueueStatus.syncing) {
        item['status'] = SyncQueueStatus.pending;
        item['updatedAt'] = DateTime.now().toIso8601String();
        changed = true;
      }
    }
    if (changed) await _writeQueue(queue);
  }

  bool _isTopicProgressQueueItem(Map<String, dynamic> item) {
    final action = item['action'] as String?;
    final type = item['type'] as String? ?? action;
    return action == 'COMPLETE_TOPIC' ||
        action == 'ADD_STUDY_HOURS' ||
        action == 'BULK_TOPIC_PROGRESS' ||
        type == 'TOPIC_PROGRESS';
  }

  bool _isStudyLogQueueItem(Map<String, dynamic> item) {
    final action = item['action'] as String?;
    final type = item['type'] as String? ?? action;
    return action == 'LOG_STUDY_HOURS' || type == 'LOG_STUDY';
  }

  Map<String, dynamic>? _payloadOf(Map<String, dynamic> item) {
    final payload = item['payload'] ?? item['payloadJson'];
    return payload is Map<String, dynamic> ? payload : null;
  }

  /// Drop queue rows already reflected in synced local tables.
  Future<int> purgeAcknowledgedItems({
    required Map<String, dynamic>? topicProgressTable,
    required Map<String, dynamic>? dailyStudyLogsTable,
  }) async {
    final queue = _readQueue();
    final before = queue.length;

    queue.removeWhere((item) {
      final payload = _payloadOf(item);
      if (payload == null) return false;

      if (_isTopicProgressQueueItem(item)) {
        final userExamId = (payload['userExamId'] as num?)?.toInt();
        final topicId = (payload['topicId'] as num?)?.toInt();
        if (userExamId == null || topicId == null) return false;
        final rowKey = LocalStore.topicProgressRowKey(userExamId, topicId);
        final row = topicProgressTable?[rowKey];
        if (row is Map<String, dynamic>) {
          return row['syncStatus'] == LocalTables.syncStatusSynced;
        }
      }

      if (_isStudyLogQueueItem(item)) {
        final studyDate = payload['studyDate'] as String?;
        if (studyDate == null) return false;
        final row = dailyStudyLogsTable?[studyDate];
        if (row is Map<String, dynamic>) {
          return row['syncStatus'] == LocalTables.syncStatusSynced;
        }
      }

      return false;
    });

    if (queue.length != before) {
      await _writeQueue(queue);
    }
    return before - queue.length;
  }

  Future<void> removeTopicProgressFor({
    required int userExamId,
    required int topicId,
  }) async {
    final queue = _readQueue()
      ..removeWhere((item) {
        if (!_isTopicProgressQueueItem(item)) return false;
        final payload = _payloadOf(item);
        if (payload == null) return false;
        return (payload['userExamId'] as num?)?.toInt() == userExamId &&
            (payload['topicId'] as num?)?.toInt() == topicId;
      });
    await _writeQueue(queue);
  }

  Future<void> removeStudyLogsForDate(String studyDate) async {
    final queue = _readQueue()
      ..removeWhere((item) {
        if (!_isStudyLogQueueItem(item)) return false;
        final payload = _payloadOf(item);
        return payload?['studyDate'] == studyDate;
      });
    await _writeQueue(queue);
  }
}
