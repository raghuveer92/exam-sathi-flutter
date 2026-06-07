import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/local/local_store.dart';
import '../../../core/sync/sync_progress.dart';
import '../../../core/sync/sync_service.dart';
import '../../../data/repositories/dashboard_repository.dart';

/// Shown after first login — downloads all data before normal usage.
class OfflineSetupScreen extends StatefulWidget {
  const OfflineSetupScreen({super.key});

  @override
  State<OfflineSetupScreen> createState() => _OfflineSetupScreenState();
}

class _OfflineSetupScreenState extends State<OfflineSetupScreen> {
  SyncProgress _progress = const SyncProgress(step: SyncStep.preparing);
  String? _error;

  @override
  void initState() {
    super.initState();
    _runDownload();
  }

  Future<void> _runDownload() async {
    setState(() {
      _error = null;
      _progress = const SyncProgress(step: SyncStep.preparing);
    });
    try {
      await GetIt.I<SyncService>().initialDownload(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      await GetIt.I<DashboardRepository>().syncDailyTargetFromProfile();
      await GetIt.I<LocalStore>().markInitialDownloadComplete();
      if (!mounted) return;
      context.go('/home');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_download_outlined,
                  size: 72, color: AppColors.primary),
              const SizedBox(height: 24),
              Text(
                _error == null ? 'Preparing Offline Content' : 'Download Failed',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                _error ?? _progress.step.label,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                textAlign: TextAlign.center,
              ),
              if (_progress.detail != null) ...[
                const SizedBox(height: 8),
                Text(
                  _progress.detail!,
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 32),
              if (_error == null) ...[
                LinearProgressIndicator(
                  value: _progress.total > 0 ? _progress.fraction : null,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 8),
                if (_progress.total > 0)
                  Text('${_progress.current} / ${_progress.total}'),
              ] else ...[
                ElevatedButton(
                  onPressed: _runDownload,
                  child: const Text('Retry Download'),
                ),
                TextButton(
                  onPressed: () => context.go('/home'),
                  child: const Text('Continue with cached data'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
