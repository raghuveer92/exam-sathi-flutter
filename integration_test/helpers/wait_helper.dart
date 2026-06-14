import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../config/test_config.dart';

typedef RetryAction = Future<void> Function();

/// Robust wait utilities with optional retry (max 2 retries by default).
class WaitHelper {
  WaitHelper(this.tester);

  final WidgetTester tester;
  static const maxRetries = 2;

  Future<void> waitForElement(
    Finder finder, {
    Duration? timeout,
    Duration pollInterval = const Duration(milliseconds: 200),
  }) async {
    final limit = timeout ?? TestConfig.defaultTimeout;
    final end = DateTime.now().add(limit);

    while (DateTime.now().isBefore(end)) {
      await tester.pump(pollInterval);
      if (finder.evaluate().isNotEmpty) return;
    }

    throw TimeoutException(
      'Element not found within ${limit.inSeconds}s: $finder',
      limit,
    );
  }

  Future<void> waitForElementToDisappear(
    Finder finder, {
    Duration? timeout,
    Duration pollInterval = const Duration(milliseconds: 200),
  }) async {
    final limit = timeout ?? TestConfig.defaultTimeout;
    final end = DateTime.now().add(limit);

    while (DateTime.now().isBefore(end)) {
      await tester.pump(pollInterval);
      if (finder.evaluate().isEmpty) return;
    }

    throw TimeoutException(
      'Element still visible after ${limit.inSeconds}s: $finder',
      limit,
    );
  }

  Future<void> pumpUntilSettled({
    Duration? timeout,
    Duration phase = const Duration(milliseconds: 100),
  }) async {
    final limit = timeout ?? TestConfig.pumpSettleTimeout;
    final end = DateTime.now().add(limit);
    var previous = 0;

    while (DateTime.now().isBefore(end)) {
      await tester.pump(phase);
      final pending = tester.binding.transientCallbackCount;
      if (pending == 0 && previous == 0) return;
      previous = pending;
    }
  }

  Future<void> withRetry(
    RetryAction action, {
    int maxAttempts = maxRetries + 1,
    Duration delay = const Duration(milliseconds: 500),
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await action();
        return;
      } catch (e) {
        lastError = e;
        if (attempt == maxAttempts) break;
        await tester.pump(delay);
      }
    }
    throw lastError ?? StateError('Retry failed');
  }
}
