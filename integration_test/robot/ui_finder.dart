import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:student_app_flutter/core/testing/test_keys.dart';

/// Smart finder with key-first strategy and text/type fallbacks.
class UiFinder {
  UiFinder(this.tester);

  final WidgetTester tester;

  Finder findByKey(Key key) => find.byKey(key);

  Finder findByText(String text, {bool exact = false}) =>
      exact ? find.text(text) : find.textContaining(text);

  Finder fallbackByType<T extends Widget>() => find.byType(T);

  /// Walks common widget types when keys and text fail.
  Finder fallbackByWidgetTree({
    Type? preferredType,
    String? textHint,
  }) {
    if (preferredType != null) {
      final typed = find.byType(preferredType);
      if (typed.evaluate().isNotEmpty) return typed;
    }
    if (textHint != null) {
      final byText = findByText(textHint);
      if (byText.evaluate().isNotEmpty) return byText;
    }
    for (final type in const [
      ElevatedButton,
      FilledButton,
      TextButton,
      TextFormField,
      TextField,
      ListTile,
      InkWell,
      GestureDetector,
    ]) {
      final finder = find.byType(type);
      if (finder.evaluate().isNotEmpty) return finder;
    }
    return find.byType(Widget);
  }

  /// Resolves a finder using key → text → type chain.
  Finder smart({
    Key? key,
    String? text,
    Type? type,
  }) {
    if (key != null) {
      final byKey = findByKey(key);
      if (byKey.evaluate().isNotEmpty) return byKey;
    }
    if (text != null) {
      final byText = findByText(text);
      if (byText.evaluate().isNotEmpty) return byText;
    }
    if (type != null) {
      return find.byType(type);
    }
    return find.byKey(key ?? TestKeys.loginSubmit);
  }
}
