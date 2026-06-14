import 'package:flutter_test/flutter_test.dart';

import 'package:student_app_flutter/core/testing/test_keys.dart';

import '../robot/test_agent.dart';

/// Waits for post-enrollment offline download before study flows.
extension EnrollmentSyncWait on TestAgent {
  Future<void> waitForEnrollmentSync() async {
    await runStep('Wait for enrollment content download', () async {
      final offline = find.byKey(TestKeys.offlineSetupScreen);
      final dashboard = find.byKey(TestKeys.dashboardScreen);
      final retryDownload = find.text('Retry Download');
      final deadline = DateTime.now().add(const Duration(seconds: 30));

      // Offline setup may appear shortly after confirm — do not skip early.
      while (DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 200));
        if (offline.evaluate().isNotEmpty) break;
        if (dashboard.evaluate().isNotEmpty) break;
      }

      if (offline.evaluate().isNotEmpty) {
        // One automatic retry if subject resolution was still in flight.
        if (retryDownload.evaluate().isNotEmpty) {
          await tap(retryDownload);
          await pumpUntilIdle();
        }

        await wait.waitForElementToDisappear(
          offline,
          timeout: const Duration(minutes: 5),
        );
      }

      await waitForElementKey(
        TestKeys.dashboardScreen,
        timeout: const Duration(seconds: 120),
      );
      await pumpUntilIdle();
    });
  }
}
