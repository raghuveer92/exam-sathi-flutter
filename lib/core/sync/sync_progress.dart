/// Steps shown during initial download / manual sync.
enum SyncStep {
  preparing('Preparing offline content'),
  userData('Downloading profile & goals'),
  bundle('Syncing profile & exams'),
  catalog('Downloading syllabus catalog'),
  subjects('Downloading subjects'),
  chapters('Downloading chapters'),
  topics('Downloading topics'),
  materializing('Saving syllabus offline'),
  mockTests('Downloading mock tests'),
  questions('Downloading questions'),
  progress('Applying study progress'),
  uploading('Uploading local changes'),
  finalizing('Finalizing offline setup'),
  complete('Download complete');

  const SyncStep(this.label);
  final String label;
}

enum SyncProgressItemStatus { pending, running, done, failed }

class SyncProgressItem {
  final String id;
  final String label;
  final SyncProgressItemStatus status;
  final String? detail;

  const SyncProgressItem({
    required this.id,
    required this.label,
    this.status = SyncProgressItemStatus.pending,
    this.detail,
  });

  SyncProgressItem copyWith({
    String? label,
    SyncProgressItemStatus? status,
    String? detail,
    bool clearDetail = false,
  }) {
    return SyncProgressItem(
      id: id,
      label: label ?? this.label,
      status: status ?? this.status,
      detail: clearDetail ? null : (detail ?? this.detail),
    );
  }
}

class SyncProgress {
  final SyncStep step;
  final int current;
  final int total;
  final String? detail;
  final List<SyncProgressItem>? steps;

  const SyncProgress({
    required this.step,
    this.current = 0,
    this.total = 0,
    this.detail,
    this.steps,
  });

  double get fraction {
    if (steps != null && steps!.isNotEmpty) {
      final done = steps!.where((s) => s.status == SyncProgressItemStatus.done).length;
      final running = steps!.any((s) => s.status == SyncProgressItemStatus.running);
      final progress = done + (running ? 0.35 : 0);
      return (progress / steps!.length).clamp(0.0, 1.0);
    }
    return total <= 0 ? 0 : (current / total).clamp(0.0, 1.0);
  }

  /// Enrollment download checklist (onboarding / add exam).
  static List<SyncProgressItem> enrollmentTemplate() => const [
        SyncProgressItem(
          id: 'enrollments',
          label: 'Finding your exam enrollment',
        ),
        SyncProgressItem(
          id: 'bundle',
          label: 'Syncing profile & progress',
        ),
        SyncProgressItem(
          id: 'catalog',
          label: 'Downloading syllabus catalog',
        ),
        SyncProgressItem(
          id: 'syllabus',
          label: 'Saving subjects & topics offline',
        ),
        SyncProgressItem(
          id: 'progress',
          label: 'Applying study progress',
        ),
        SyncProgressItem(
          id: 'finalize',
          label: 'Finalizing offline setup',
        ),
      ];

  /// First-login full download checklist.
  static List<SyncProgressItem> fullDownloadTemplate() => const [
        SyncProgressItem(
          id: 'profile',
          label: 'Refreshing your profile',
        ),
        SyncProgressItem(
          id: 'bundle',
          label: 'Syncing exams & progress data',
        ),
        SyncProgressItem(
          id: 'subjects',
          label: 'Downloading subjects & topics',
        ),
        SyncProgressItem(
          id: 'catalog',
          label: 'Downloading syllabus catalog',
        ),
        SyncProgressItem(
          id: 'mocktests',
          label: 'Downloading mock tests',
        ),
        SyncProgressItem(
          id: 'finalize',
          label: 'Building offline views',
        ),
      ];

  static SyncProgress withActiveStep({
    required List<SyncProgressItem> template,
    required String activeId,
    SyncStep step = SyncStep.preparing,
    String? detail,
    int current = 0,
    int total = 0,
  }) {
    final activeIndex = template.indexWhere((s) => s.id == activeId);
    if (activeIndex < 0) {
      return SyncProgress(step: step, detail: detail, steps: template);
    }

    final steps = [
      for (var i = 0; i < template.length; i++)
        template[i].copyWith(
          status: i < activeIndex
              ? SyncProgressItemStatus.done
              : i == activeIndex
                  ? SyncProgressItemStatus.running
                  : SyncProgressItemStatus.pending,
          detail: i == activeIndex ? detail : template[i].detail,
          clearDetail: i != activeIndex && i >= activeIndex,
        ),
    ];

    return SyncProgress(
      step: step,
      current: activeIndex,
      total: template.length,
      detail: detail,
      steps: steps,
    );
  }

  static SyncProgress withCompletedSteps({
    required List<SyncProgressItem> template,
    required String throughId,
    SyncStep step = SyncStep.preparing,
    String? detail,
  }) {
    final throughIndex = template.indexWhere((s) => s.id == throughId);
    if (throughIndex < 0) {
      return SyncProgress(step: step, detail: detail, steps: template);
    }

    final steps = [
      for (var i = 0; i < template.length; i++)
        template[i].copyWith(
          status: i <= throughIndex
              ? SyncProgressItemStatus.done
              : SyncProgressItemStatus.pending,
          detail: i == throughIndex ? detail : template[i].detail,
          clearDetail: i > throughIndex,
        ),
    ];

    return SyncProgress(
      step: step,
      current: throughIndex + 1,
      total: template.length,
      detail: detail,
      steps: steps,
    );
  }
}
