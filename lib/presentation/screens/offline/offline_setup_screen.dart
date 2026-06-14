import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_navigation.dart';
import '../../../core/local/local_store.dart';
import '../../../core/testing/test_keys.dart';
import '../../../core/sync/progress_rebuild_service.dart';
import '../../../core/sync/sync_progress.dart';
import '../../../core/sync/sync_service.dart';
import '../../../data/repositories/dashboard_repository.dart';
import '../../../data/repositories/progress_repository.dart';

/// Downloads syllabus — full on first login, scoped when adding an exam.
class OfflineSetupScreen extends StatefulWidget {
  final String redirectPath;
  final String title;
  final bool enrollmentOnly;
  final int? userExamId;

  const OfflineSetupScreen({
    super.key,
    this.redirectPath = '/home',
    this.title = 'Preparing Offline Content',
    this.enrollmentOnly = false,
    this.userExamId,
  });

  @override
  State<OfflineSetupScreen> createState() => _OfflineSetupScreenState();
}

class _OfflineSetupScreenState extends State<OfflineSetupScreen> {
  SyncProgress _progress = SyncProgress(
    step: SyncStep.preparing,
    steps: SyncProgress.enrollmentTemplate(),
  );
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_initDownload());
  }

  Future<bool> _shouldSkipDownload() async {
    final store = GetIt.I<LocalStore>();
    final progressRepo = GetIt.I<ProgressRepository>();

    if (widget.enrollmentOnly) {
      final userExamId = widget.userExamId;
      if (userExamId != null &&
          progressRepo.enrollmentHasCachedTopics(userExamId)) {
        return true;
      }
      if (store.isInitialDownloadComplete() &&
          progressRepo.hasOfflineStudyContent()) {
        return true;
      }
      return false;
    }

    return store.isInitialDownloadComplete() &&
        progressRepo.hasOfflineStudyContent();
  }

  Future<void> _initDownload() async {
    if (await _shouldSkipDownload()) {
      final store = GetIt.I<LocalStore>();
      if (!store.isInitialDownloadComplete()) {
        await store.markInitialDownloadComplete();
      }
      if (!mounted) return;
      AppNavigation.resetTo(context, widget.redirectPath);
      return;
    }
    await _runDownload();
  }

  Future<void> _runDownload() async {
    setState(() {
      _error = null;
      _progress = SyncProgress(
        step: SyncStep.preparing,
        steps: widget.enrollmentOnly
            ? SyncProgress.enrollmentTemplate()
            : SyncProgress.fullDownloadTemplate(),
      );
    });
    try {
      final sync = GetIt.I<SyncService>();
      if (widget.enrollmentOnly) {
        await sync.downloadEnrollmentContent(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          userExamId: widget.userExamId,
        );
        final store = GetIt.I<LocalStore>();
        if (!store.isInitialDownloadComplete()) {
          await GetIt.I<DashboardRepository>().reconcileDashboardCache();
          await store.markInitialDownloadComplete();
        }
      } else {
        await sync.downloadAllContent(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
        );
        await GetIt.I<DashboardRepository>().reconcileDashboardCache();
        await GetIt.I<ProgressRebuildService>().rebuildAll();
        await GetIt.I<LocalStore>().markInitialDownloadComplete();
      }
      if (!mounted) return;
      AppNavigation.resetTo(context, widget.redirectPath);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  SyncProgressItem? get _activeStep {
    final steps = _progress.steps;
    if (steps == null) return null;
    for (final step in steps) {
      if (step.status == SyncProgressItemStatus.running) return step;
    }
    return null;
  }

  void _handleSystemBack() {
    final store = GetIt.I<LocalStore>();
    if (store.isInitialDownloadComplete()) {
      AppNavigation.resetTo(context, widget.redirectPath);
      return;
    }
    AppNavigation.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final steps = _progress.steps;
    final activeStep = _activeStep;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleSystemBack();
      },
      child: Scaffold(
      key: TestKeys.offlineSetupScreen,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Icon(
                _error == null
                    ? Icons.cloud_download_outlined
                    : Icons.cloud_off_outlined,
                size: 64,
                color: _error == null ? AppColors.primary : AppColors.error,
              ),
              const SizedBox(height: 20),
              Text(
                _error == null ? widget.title : 'Download Failed',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _error ??
                    (activeStep?.label ?? _progress.step.label),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                textAlign: TextAlign.center,
              ),
              if (_error == null &&
                  activeStep?.detail != null &&
                  activeStep!.detail!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  activeStep.detail!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 28),
              if (_error == null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: _progress.fraction > 0 ? _progress.fraction : null,
                    minHeight: 8,
                    backgroundColor: AppColors.shimmerBase,
                  ),
                ),
                if (steps != null && steps.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${steps.where((s) => s.status == SyncProgressItemStatus.done).length} of ${steps.length} steps complete',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                Expanded(
                  child: steps != null && steps.isNotEmpty
                      ? _DownloadStepList(steps: steps)
                      : Center(
                          child: Text(
                            _progress.detail ?? 'Please wait…',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                ),
              ] else ...[
                const Spacer(),
                ElevatedButton(
                  onPressed: _runDownload,
                  child: const Text('Retry Download'),
                ),
                TextButton(
                  onPressed: () => AppNavigation.resetTo(context, widget.redirectPath),
                  child: const Text('Continue with cached data'),
                ),
                const Spacer(),
              ],
            ],
          ),
        ),
      ),
    ),
    );
  }
}

class _DownloadStepList extends StatelessWidget {
  const _DownloadStepList({required this.steps});

  final List<SyncProgressItem> steps;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: steps.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = steps[index];
        return _DownloadStepTile(item: item);
      },
    );
  }
}

class _DownloadStepTile extends StatelessWidget {
  const _DownloadStepTile({required this.item});

  final SyncProgressItem item;

  @override
  Widget build(BuildContext context) {
    final isRunning = item.status == SyncProgressItemStatus.running;
    final isDone = item.status == SyncProgressItemStatus.done;
    final isFailed = item.status == SyncProgressItemStatus.failed;

    final Color borderColor = isRunning
        ? AppColors.primary.withValues(alpha: 0.35)
        : isDone
            ? AppColors.success.withValues(alpha: 0.25)
            : const Color(0xFFE8EAF0);
    final Color background = isRunning
        ? AppColors.primary.withValues(alpha: 0.06)
        : Colors.white;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StepStatusIcon(
            status: item.status,
            isRunning: isRunning,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: TextStyle(
                    fontWeight: isRunning ? FontWeight.w700 : FontWeight.w600,
                    color: isRunning || isDone
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                ),
                if (item.detail != null && item.detail!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.detail!,
                    style: TextStyle(
                      fontSize: 12,
                      color: isFailed
                          ? AppColors.error
                          : isRunning
                              ? AppColors.primary
                              : AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepStatusIcon extends StatelessWidget {
  const _StepStatusIcon({
    required this.status,
    required this.isRunning,
  });

  final SyncProgressItemStatus status;
  final bool isRunning;

  @override
  Widget build(BuildContext context) {
    if (status == SyncProgressItemStatus.done) {
      return const Icon(Icons.check_circle, color: AppColors.success, size: 22);
    }
    if (status == SyncProgressItemStatus.failed) {
      return const Icon(Icons.error_outline, color: AppColors.error, size: 22);
    }
    if (isRunning) {
      return SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: AppColors.primary.withValues(alpha: 0.9),
        ),
      );
    }
    return Icon(
      Icons.radio_button_unchecked,
      size: 22,
      color: AppColors.textHint.withValues(alpha: 0.55),
    );
  }
}
