/// Steps shown during initial download / manual sync.
enum SyncStep {
  preparing('Preparing offline content'),
  userData('Downloading profile & goals'),
  subjects('Downloading subjects'),
  chapters('Downloading chapters'),
  topics('Downloading topics'),
  mockTests('Downloading mock tests'),
  questions('Downloading questions'),
  progress('Downloading progress'),
  uploading('Uploading local changes'),
  complete('Download complete');

  const SyncStep(this.label);
  final String label;
}

class SyncProgress {
  final SyncStep step;
  final int current;
  final int total;
  final String? detail;

  const SyncProgress({
    required this.step,
    this.current = 0,
    this.total = 0,
    this.detail,
  });

  double get fraction =>
      total <= 0 ? 0 : (current / total).clamp(0.0, 1.0);
}
