import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../core/constants/app_colors.dart';
import '../../core/sync/offline_queue_service.dart';
import '../../core/sync/sync_service.dart';

enum _IndicatorState { synced, syncing, pending }

/// Tiny non-blocking sync status icon — ✔ synced, ⟳ syncing, ⚠ pending.
class SyncStatusIndicator extends StatelessWidget {
  const SyncStatusIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = GetIt.I<SyncService>();
    final queue = GetIt.I<OfflineQueueService>();

    return StreamBuilder<SyncStatus>(
      stream: sync.statusStream,
      initialData: sync.status,
      builder: (context, syncSnap) {
        return ValueListenableBuilder<int>(
          valueListenable: queue.pendingCountListenable,
          builder: (context, pending, _) {
            final state = _resolveState(syncSnap.data, pending, sync.isSyncing);
            if (state == _IndicatorState.synced) {
              return const SizedBox.shrink();
            }
            return Tooltip(
              message: _tooltip(state, pending),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  _icon(state),
                  size: 18,
                  color: _color(state),
                ),
              ),
            );
          },
        );
      },
    );
  }

  _IndicatorState _resolveState(
    SyncStatus? status,
    int pending,
    bool isSyncing,
  ) {
    if (isSyncing || status == SyncStatus.syncing) {
      return _IndicatorState.syncing;
    }
    if (pending > 0 ||
        status == SyncStatus.offline ||
        status == SyncStatus.failed) {
      return _IndicatorState.pending;
    }
    return _IndicatorState.synced;
  }

  IconData _icon(_IndicatorState state) => switch (state) {
        _IndicatorState.syncing => Icons.sync,
        _IndicatorState.pending => Icons.cloud_upload_outlined,
        _IndicatorState.synced => Icons.cloud_done_outlined,
      };

  Color _color(_IndicatorState state) => switch (state) {
        _IndicatorState.syncing => AppColors.primary,
        _IndicatorState.pending => const Color(0xFFE6A700),
        _IndicatorState.synced => AppColors.textHint,
      };

  String _tooltip(_IndicatorState state, int pending) => switch (state) {
        _IndicatorState.syncing => 'Syncing in background…',
        _IndicatorState.pending => pending > 0
            ? '$pending change${pending == 1 ? '' : 's'} waiting to sync'
            : 'Sync pending — will retry when online',
        _IndicatorState.synced => 'All changes synced',
      };
}
