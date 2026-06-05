import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../core/sync/sync_service.dart';

/// Shows when the app is using cached data or is offline.
class OfflineModeBanner extends StatelessWidget {
  const OfflineModeBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyncStatus>(
      stream: GetIt.I<SyncService>().statusStream,
      initialData: GetIt.I<SyncService>().status,
      builder: (context, snapshot) {
        final status = snapshot.data ?? SyncStatus.idle;
        if (status != SyncStatus.offline && status != SyncStatus.failed) {
          return const SizedBox.shrink();
        }
        final label = status == SyncStatus.offline
            ? 'Offline mode — using cached data'
            : 'Sync failed — showing cached data';
        return Material(
          color: status == SyncStatus.offline
              ? const Color(0xFF37474F)
              : const Color(0xFF8D6E63),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    status == SyncStatus.offline ? Icons.cloud_off : Icons.sync_problem,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
