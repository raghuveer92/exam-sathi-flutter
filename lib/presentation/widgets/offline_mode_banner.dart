import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../core/sync/offline_queue_service.dart';

/// Shows pending sync count — offline-first mode is normal, not an error.
class OfflineModeBanner extends StatelessWidget {
  const OfflineModeBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final queue = GetIt.I<OfflineQueueService>();
    return ValueListenableBuilder<int>(
      valueListenable: queue.pendingCountListenable,
      builder: (context, pending, _) {
        if (pending == 0) return const SizedBox.shrink();

        return Material(
          color: const Color(0xFF37474F),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.cloud_upload_outlined,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$pending change${pending == 1 ? '' : 's'} waiting to sync — tap SYNC when online',
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
