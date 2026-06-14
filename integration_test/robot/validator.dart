import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:student_app_flutter/core/local/api_call_tracker.dart';

import '../helpers/wait_helper.dart';
import 'ui_finder.dart';

/// Assertion helpers for integration tests.
class Validator {
  Validator(this.tester, this.finder, this.wait);

  final WidgetTester tester;
  final UiFinder finder;
  final WaitHelper wait;

  Future<void> assertVisible(
    Finder target, {
    Duration? timeout,
    String? message,
  }) async {
    await wait.waitForElement(target, timeout: timeout);
    expect(target, findsWidgets, reason: message);
  }

  Future<void> assertVisibleKey(Key key, {String? message}) =>
      assertVisible(finder.findByKey(key), message: message);

  Future<void> assertTextExists(String text, {bool exact = false}) async {
    final target = finder.findByText(text, exact: exact);
    await assertVisible(target, message: 'Expected text: $text');
  }

  Future<void> assertApiSuccess(
    String endpointFragment, {
    Duration timeout = const Duration(seconds: 30),
    int minCalls = 1,
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 200));
      final calls = ApiCallTracker.instance.byEndpoint.entries
          .where((e) => e.key.contains(endpointFragment))
          .fold<int>(0, (sum, e) => sum + e.value);
      if (calls >= minCalls) return;
    }
    throw TestFailure(
      'Expected API call containing "$endpointFragment" (min $minCalls)',
    );
  }

  Future<void> assertNavigation({
    Key? screenKey,
    String? routeText,
  }) async {
    if (screenKey != null) {
      await assertVisibleKey(screenKey);
      return;
    }
    if (routeText != null) {
      await assertTextExists(routeText);
      return;
    }
    throw ArgumentError('Provide screenKey or routeText');
  }

  Future<void> assertNotVisible(Finder target, {Duration? timeout}) async {
    await wait.waitForElementToDisappear(target, timeout: timeout);
  }
}
