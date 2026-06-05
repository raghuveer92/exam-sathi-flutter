import 'package:uuid/uuid.dart';

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

  List<Map<String, dynamic>> _readQueue() {
    final list = _store.getJsonList(LocalStore.offlineQueueKey);
    if (list == null) return [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> _writeQueue(List<Map<String, dynamic>> items) async {
    await _store.putJson(LocalStore.offlineQueueKey, items);
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

  Future<bool> flush({bool force = false}) async {
    final queue = _readQueue();
    if (queue.isEmpty) return true;

    final pushItems = queue
        .where((e) =>
            e['action'] != 'SUBMIT_TEST' && e['syncStatus'] != 'synced')
        .map((e) => {
              'clientId': e['clientId'],
              'type': e['type'] ?? e['action'],
              'payload': e['payload'],
              'createdAt': e['createdAt'],
            })
        .toList();

    if (pushItems.isNotEmpty) {
      try {
        await _syncRepository.pushChanges(pushItems);
      } catch (_) {
        if (!force) rethrow;
        return false;
      }
    }

    final remaining = <Map<String, dynamic>>[];
    for (final item in queue) {
      if (item['action'] == 'SUBMIT_TEST') {
        remaining.add(item);
      }
    }
    await _writeQueue(remaining);
    return true;
  }

  Future<void> removeByClientId(String clientId) async {
    final queue = _readQueue()
      ..removeWhere((e) => e['clientId'] == clientId);
    await _writeQueue(queue);
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
