import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/wait_helper.dart';
import 'ui_finder.dart';

/// Low-level UI interactions shared by [TestAgent].
class UiActions {
  UiActions(this.tester, this.finder, this.wait);

  final WidgetTester tester;
  final UiFinder finder;
  final WaitHelper wait;

  Future<void> tap(Finder target) async {
    await wait.waitForElement(target);
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
  }

  Future<void> tapKey(Key key) async {
    final root = find.byKey(key);
    for (final type in <Type>[
      ElevatedButton,
      FilledButton,
      TextButton,
      OutlinedButton,
      InkWell,
      IconButton,
    ]) {
      final interactive = find.descendant(
        of: root,
        matching: find.byType(type),
      );
      if (interactive.evaluate().isNotEmpty) {
        await tap(interactive.first);
        return;
      }
    }
    await tap(root);
  }

  Future<void> scrollUntilVisible(
    Finder target, {
    Finder? scrollable,
    double delta = 80,
    int maxScrolls = 20,
  }) async {
    await wait.waitForElement(target);
    if (await _tryEnsureVisible(target)) return;

    // Fixed footers (e.g. topic selection bar) are outside the body scroll view.
    if (scrollable == null) {
      await tester.ensureVisible(target);
      return;
    }

    for (var i = 0; i < maxScrolls; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (await _tryEnsureVisible(target)) return;
      await tester.drag(scrollable, Offset(0, -delta));
      await tester.pump();
    }
    await tester.ensureVisible(target);
  }

  Future<bool> _tryEnsureVisible(Finder target) async {
    try {
      await tester.ensureVisible(target);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> enterText(Finder field, String value) async {
    await wait.waitForElement(field);
    await tester.ensureVisible(field);
    await tester.tap(field);
    await tester.pump();
    await tester.enterText(field, value);
    await tester.pump();
  }

  Future<void> enterTextKey(Key key, String value) =>
      enterText(finder.findByKey(key), value);

  Future<void> scroll({
    Finder? scrollable,
    double delta = -300,
  }) async {
    final target = scrollable ?? find.byType(Scrollable).first;
    await tester.drag(target, Offset(0, delta));
    await tester.pump();
  }

  Future<void> navigateBack() async {
    final back = find.byTooltip('Back');
    if (back.evaluate().isNotEmpty) {
      await tap(back);
      return;
    }
    final iconBack = find.byIcon(Icons.arrow_back);
    if (iconBack.evaluate().isNotEmpty) {
      await tap(iconBack.first);
    }
  }

  Future<void> dismissKeyboard() async {
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
  }
}
