import 'package:uuid/uuid.dart';

import '../local/local_store.dart';
import '../../data/repositories/sync_repository.dart';

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

  Future<void> enqueue({
    required String type,
    required Map<String, dynamic> payload,
  }) async {
    final queue = _readQueue();
    queue.add({
      'clientId': _uuid.v4(),
      'type': type,
      'payload': payload,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await _writeQueue(queue);
  }

  int get pendingCount => _readQueue().length;

  Future<bool> flush({bool force = false}) async {
    final queue = _readQueue();
    if (queue.isEmpty) return true;
    try {
      await _syncRepository.pushChanges(queue);
      await _writeQueue([]);
      return true;
    } catch (_) {
      if (!force) rethrow;
      return false;
    }
  }
}
