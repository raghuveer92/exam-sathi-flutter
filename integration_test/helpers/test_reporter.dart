import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Structured step logging for integration tests.
class TestLogger {
  TestLogger({this.verbose = true});

  final bool verbose;
  final List<String> _lines = [];

  List<String> get lines => List.unmodifiable(_lines);

  void step(String name, {required bool success, String? detail}) {
    final ts = DateTime.now().toIso8601String();
    final status = success ? 'PASS' : 'FAIL';
    final line = '[$ts] [$status] $name${detail != null ? ' — $detail' : ''}';
    _lines.add(line);
    if (verbose) {
      debugPrint('[ExamSaathi E2E] $line');
    }
  }

  void info(String message) {
    final line = '[${DateTime.now().toIso8601String()}] [INFO] $message';
    _lines.add(line);
    if (verbose) debugPrint('[ExamSaathi E2E] $line');
  }

  void error(String message, [Object? error]) {
    final line =
        '[${DateTime.now().toIso8601String()}] [ERROR] $message${error != null ? ': $error' : ''}';
    _lines.add(line);
    debugPrint('[ExamSaathi E2E] $line');
  }
}

/// Aggregates run results into a CI-friendly report.
class TestReporter {
  TestReporter({required this.suiteName});

  final String suiteName;
  final DateTime _startedAt = DateTime.now();
  final List<TestStepResult> _steps = [];

  void recordStep(String name, {required bool success, String? detail}) {
    _steps.add(TestStepResult(
      name: name,
      success: success,
      timestamp: DateTime.now(),
      detail: detail,
    ));
  }

  TestRunReport buildReport() {
    final passed = _steps.where((s) => s.success).length;
    final failed = _steps.length - passed;
    return TestRunReport(
      suite: suiteName,
      startedAt: _startedAt,
      finishedAt: DateTime.now(),
      passedSteps: passed,
      failedSteps: failed,
      steps: List.unmodifiable(_steps),
    );
  }

  Future<void> writeJsonReport({String? path}) async {
    if (kIsWeb) return;
    final report = buildReport();
    final filePath = path ??
        'integration_test/reports/latest_report.json';
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(report.toJson()));
  }

  void printSummary() {
    final report = buildReport();
    debugPrint('\n${'=' * 60}');
    debugPrint('ExamSaathi Integration Test Report');
    debugPrint('Suite: ${report.suite}');
    debugPrint('Duration: ${report.durationMs}ms');
    debugPrint('Passed: ${report.passedSteps} | Failed: ${report.failedSteps}');
    for (final step in report.steps) {
      debugPrint(
        '  ${step.success ? '✓' : '✗'} ${step.name}${step.detail != null ? ' (${step.detail})' : ''}',
      );
    }
    debugPrint('${'=' * 60}\n');
  }
}

class TestStepResult {
  const TestStepResult({
    required this.name,
    required this.success,
    required this.timestamp,
    this.detail,
  });

  final String name;
  final bool success;
  final DateTime timestamp;
  final String? detail;

  Map<String, dynamic> toJson() => {
        'name': name,
        'success': success,
        'timestamp': timestamp.toIso8601String(),
        if (detail != null) 'detail': detail,
      };
}

class TestRunReport {
  const TestRunReport({
    required this.suite,
    required this.startedAt,
    required this.finishedAt,
    required this.passedSteps,
    required this.failedSteps,
    required this.steps,
  });

  final String suite;
  final DateTime startedAt;
  final DateTime finishedAt;
  final int passedSteps;
  final int failedSteps;
  final List<TestStepResult> steps;

  int get durationMs => finishedAt.difference(startedAt).inMilliseconds;

  Map<String, dynamic> toJson() => {
        'suite': suite,
        'startedAt': startedAt.toIso8601String(),
        'finishedAt': finishedAt.toIso8601String(),
        'durationMs': durationMs,
        'passedSteps': passedSteps,
        'failedSteps': failedSteps,
        'steps': steps.map((s) => s.toJson()).toList(),
      };
}
