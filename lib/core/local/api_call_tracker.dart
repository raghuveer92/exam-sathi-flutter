import 'package:logger/logger.dart';

/// Tracks API calls and timings for offline-first performance reporting.
class ApiCallTracker {
  static final ApiCallTracker instance = ApiCallTracker._();
  ApiCallTracker._();

  int _sessionCalls = 0;
  final Map<String, int> _byEndpoint = {};
  final List<ApiCallTiming> _timings = [];

  void record(String endpoint) {
    _sessionCalls++;
    _byEndpoint[endpoint] = (_byEndpoint[endpoint] ?? 0) + 1;
  }

  void recordTimed(
    String endpoint,
    int durationMs, {
    int? statusCode,
    String? detail,
  }) {
    record(endpoint);
    _timings.add(
      ApiCallTiming(
        endpoint: endpoint,
        durationMs: durationMs,
        statusCode: statusCode,
        detail: detail,
        at: DateTime.now(),
      ),
    );
  }

  int get sessionCalls => _sessionCalls;

  Map<String, int> get byEndpoint => Map.unmodifiable(_byEndpoint);

  List<ApiCallTiming> get timings => List.unmodifiable(_timings);

  void reset() {
    _sessionCalls = 0;
    _byEndpoint.clear();
    _timings.clear();
  }

  /// Prints slowest endpoints first — call at end of a download/sync run.
  void logSummary(Logger logger, {String tag = 'Download API'}) {
    if (_timings.isEmpty) {
      logger.i('[$tag] no timed HTTP calls recorded');
      return;
    }

    final totalMs =
        _timings.fold<int>(0, (sum, row) => sum + row.durationMs);
    logger.i(
      '[$tag] ${_timings.length} HTTP call(s), ${totalMs}ms total wall time',
    );

    final grouped = <String, List<int>>{};
    for (final row in _timings) {
      grouped.putIfAbsent(row.endpoint, () => []).add(row.durationMs);
    }

    final ranked = grouped.entries.toList()
      ..sort(
        (a, b) => b.value
            .fold<int>(0, (s, ms) => s + ms)
            .compareTo(a.value.fold<int>(0, (s, ms) => s + ms)),
      );

    for (final entry in ranked) {
      final durations = entry.value;
      final sum = durations.fold<int>(0, (s, ms) => s + ms);
      final avg = sum ~/ durations.length;
      final max = durations.reduce((a, b) => a > b ? a : b);
      logger.i(
        '[$tag]   ${durations.length}× ${entry.key} — '
        'total ${sum}ms, avg ${avg}ms, max ${max}ms',
      );
    }
  }
}

class ApiCallTiming {
  const ApiCallTiming({
    required this.endpoint,
    required this.durationMs,
    required this.at,
    this.statusCode,
    this.detail,
  });

  final String endpoint;
  final int durationMs;
  final int? statusCode;
  final String? detail;
  final DateTime at;
}
