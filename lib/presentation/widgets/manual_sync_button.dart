import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../core/sync/offline_queue_service.dart';
import '../../core/sync/sync_service.dart';

/// User-triggered SYNC — uploads pending changes then downloads latest data.
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
  bool _syncing = false;

  Future<void> _runSync() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      await GetIt.I<SyncService>().manualSync();
      widget.onComplete?.call();
      if (mounted) {
        final pending = GetIt.I<OfflineQueueService>().pendingCount;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              pending == 0
                  ? 'Sync complete'
                  : 'Sync complete ($pending items still pending)',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = GetIt.I<OfflineQueueService>().pendingCount;
    if (widget.compact) {
      return IconButton(
        tooltip: 'Sync',
        onPressed: _syncing ? null : _runSync,
        icon: _syncing
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
      onPressed: _syncing ? null : _runSync,
      icon: _syncing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.sync, size: 20),
      label: Text(pending > 0 ? 'SYNC ($pending pending)' : 'SYNC'),
    );
  }
}
