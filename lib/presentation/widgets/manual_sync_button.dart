import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../core/sync/offline_queue_service.dart';
import '../../core/sync/sync_service.dart';

/// Force sync now — automatic background sync remains the primary path.
class ManualSyncButton extends StatefulWidget {
  const ManualSyncButton({
    super.key,
    this.compact = false,
    this.onComplete,
  });

  final bool compact;
  final VoidCallback? onComplete;

  @override
  State<ManualSyncButton> createState() => _ManualSyncButtonState();
}

class _ManualSyncButtonState extends State<ManualSyncButton> {
  bool _forceSyncing = false;

  Future<void> _runSync() async {
    if (_forceSyncing) return;
    setState(() => _forceSyncing = true);
    try {
      await GetIt.I<SyncService>().manualSync();
      widget.onComplete?.call();
      GetIt.I<OfflineQueueService>().refreshPendingCount();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Force sync failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _forceSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final queue = GetIt.I<OfflineQueueService>();
    final sync = GetIt.I<SyncService>();
    return StreamBuilder<SyncStatus>(
      stream: sync.statusStream,
      initialData: sync.status,
      builder: (context, syncSnap) {
        final backgroundSyncing =
            syncSnap.data == SyncStatus.syncing && !_forceSyncing;
        final syncing = _forceSyncing || backgroundSyncing;

        return ValueListenableBuilder<int>(
          valueListenable: queue.pendingCountListenable,
          builder: (context, pending, _) {
            if (widget.compact) {
              if (!syncing && pending == 0) {
                return const SizedBox.shrink();
              }
              return IconButton(
                tooltip: 'Force Sync Now',
                onPressed: syncing ? null : _runSync,
                icon: syncing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Badge(
                        isLabelVisible: pending > 0,
                        label: Text('$pending'),
                        child: const Icon(Icons.sync),
                      ),
              );
            }

            return FilledButton.icon(
              onPressed: syncing ? null : _runSync,
              icon: syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.sync, size: 20),
              label: Text(
                pending > 0
                    ? 'Force Sync Now ($pending pending)'
                    : 'Force Sync Now',
              ),
            );
          },
        );
      },
    );
  }
}
