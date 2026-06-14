import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../helpers/test_reporter.dart';
import '../helpers/wait_helper.dart';
import 'ui_actions.dart';
import 'ui_finder.dart';
import 'validator.dart';

/// User-like testing agent — primary automation interface for flows.
class TestAgent {
  TestAgent(
    this.tester, {
    TestReporter? reporter,
  }) : reporter = reporter ?? TestReporter(suiteName: 'ExamSaathi') {
    finder = UiFinder(tester);
    wait = WaitHelper(tester);
    actions = UiActions(tester, finder, wait);
    validator = Validator(tester, finder, wait);
  }

  final WidgetTester tester;
  final TestReporter reporter;
  late final UiFinder finder;
  late final WaitHelper wait;
  late final UiActions actions;
  late final Validator validator;

  String? _currentStep; // used for failure screenshot naming

  Future<void> runStep(
    String name,
    Future<void> Function() body,
  ) async {
    _currentStep = name;
    try {
      await wait.withRetry(body);
      reporter.recordStep(name, success: true);
    } catch (e, stack) {
      reporter.recordStep(name, success: false, detail: e.toString());
      await _captureFailureScreenshot(_currentStep ?? name);
      Error.throwWithStackTrace(e, stack);
    } finally {
      _currentStep = null;
    }
  }

  Future<void> tap(Finder element) => actions.tap(element);

  Future<void> tapKey(Key key) => actions.tapKey(key);

  Future<void> scrollUntilVisible(Finder target, {Finder? scrollable}) =>
      actions.scrollUntilVisible(target, scrollable: scrollable);

  Future<void> enterText(Finder field, String value) =>
      actions.enterText(field, value);

  Future<void> enterTextKey(Key key, String value) =>
      actions.enterTextKey(key, value);

  Future<void> scroll({double delta = -300}) => actions.scroll(delta: delta);

  Future<void> waitForElement(
    Finder finder, {
    Duration? timeout,
  }) =>
      wait.waitForElement(finder, timeout: timeout);

  Future<void> waitForElementKey(Key key, {Duration? timeout}) =>
      wait.waitForElement(finder.findByKey(key), timeout: timeout);

  Future<void> waitForApiResponse(
    String endpointFragment, {
    Duration timeout = const Duration(seconds: 45),
  }) =>
      validator.assertApiSuccess(endpointFragment, timeout: timeout);

  Future<void> assertVisible(Finder finder, {String? message}) =>
      validator.assertVisible(finder, message: message);

  Future<void> assertVisibleKey(Key key, {String? message}) =>
      validator.assertVisibleKey(key, message: message);

  Future<void> navigateBack() => actions.navigateBack();

  Finder smart({Key? key, String? text, Type? type}) =>
      finder.smart(key: key, text: text, type: type);

  Future<void> pumpUntilIdle() => wait.pumpUntilSettled();

  Future<void> _captureFailureScreenshot(String stepName) async {
    if (kIsWeb) return;
    try {
      final binding = IntegrationTestWidgetsFlutterBinding.instance;
      final name =
          'failure_${stepName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';
      await binding.takeScreenshot(name);
      final dir = Directory('integration_test/reports/screenshots');
      if (!dir.existsSync()) dir.createSync(recursive: true);
    } catch (_) {
      // Screenshot capture is best-effort.
    }
  }
}
