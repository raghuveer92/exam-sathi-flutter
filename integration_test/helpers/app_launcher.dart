import 'package:flutter_test/flutter_test.dart';

import 'package:student_app_flutter/main.dart' as app;

/// Starts the app once per flutter drive session (web-safe).
///
/// Avoid calling [app.main] multiple times in one drive run — Chrome loses the
/// test driver connection and shows the "Test Starting..." harness page.
Future<void> launchAppForTest(WidgetTester tester) async {
  app.main();
  await tester.pump();
  await tester.pump(const Duration(seconds: 3));
}
