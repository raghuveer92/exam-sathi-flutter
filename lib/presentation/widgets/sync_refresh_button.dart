import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../core/sync/offline_queue_service.dart';
import '../../core/sync/sync_service.dart';

/// Manual sync button — reloads local cache after SYNC completes.
class SyncRefreshButton extends StatefulWidget {
  const SyncRefreshButton({
    super.key,
    required this.onRefreshed,
    this.tooltip = 'Reload from cache',
  });

  final Future<void> Function() onRefreshed;
  final String tooltip;

  @override
  State<SyncRefreshButton> createState() => _SyncRefreshButtonState();
}

class _SyncRefreshButtonState extends State<SyncRefreshButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await GetIt.I<SyncService>().manualSync();
      await widget.onRefreshed();
      if (mounted) {
        final pending = GetIt.I<OfflineQueueService>().pendingCount;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync complete${pending > 0 ? ' ($pending pending)' : ''}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = GetIt.I<OfflineQueueService>().pendingCount;
    return IconButton(
      tooltip: widget.tooltip,
      onPressed: _busy ? null : _run,
      icon: _busy
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
}
