import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../core/sync/offline_queue_service.dart';

/// Subtle banner when changes are queued — sync runs automatically in background.
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.cloud_upload_outlined,
                      color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$pending change${pending == 1 ? '' : 's'} will sync automatically when online',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
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
