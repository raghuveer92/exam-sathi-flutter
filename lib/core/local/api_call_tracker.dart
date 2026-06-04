/// Tracks API calls for offline-first performance reporting.
class ApiCallTracker {
  static final ApiCallTracker instance = ApiCallTracker._();
  ApiCallTracker._();

  int _sessionCalls = 0;
  final Map<String, int> _byEndpoint = {};

  void record(String endpoint) {
    _sessionCalls++;
    _byEndpoint[endpoint] = (_byEndpoint[endpoint] ?? 0) + 1;
  }

  int get sessionCalls => _sessionCalls;

  Map<String, int> get byEndpoint => Map.unmodifiable(_byEndpoint);

  void reset() {
    _sessionCalls = 0;
    _byEndpoint.clear();
  }
}
