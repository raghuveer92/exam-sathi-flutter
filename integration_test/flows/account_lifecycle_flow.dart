import 'package:flutter_test/flutter_test.dart';

import 'package:student_app_flutter/core/testing/test_keys.dart';

import '../flows/auth_flow.dart';
import '../helpers/sync_helper.dart';
import '../robot/test_agent.dart';

/// Logout → login → verify persistence → delete account.
class AccountLifecycleFlow {
  AccountLifecycleFlow(this.agent);

  final TestAgent agent;

  Future<void> deleteAccountOnly(AuthSession session) async {
    await agent.runStep('Open profile', () async {
      await agent.tapKey(TestKeys.navProfile);
      await agent.pumpUntilIdle();
      await agent.wait.waitForElement(
        find.text('Profile'),
        timeout: const Duration(seconds: 30),
      );
    });

    await agent.runStep('Delete account', () async {
      await agent.scrollUntilVisible(find.byKey(TestKeys.profileDeleteAccount));
      await agent.tapKey(TestKeys.profileDeleteAccount);
      await agent.pumpUntilIdle();
      if (find.byKey(TestKeys.deleteAccountPassword).evaluate().isNotEmpty) {
        await agent.enterTextKey(
          TestKeys.deleteAccountPassword,
          session.user.password,
        );
      }
      await agent.tapKey(TestKeys.deleteAccountConfirm);
      await agent.pumpUntilIdle();
      await agent.waitForElementKey(TestKeys.loginEmail);
    });

    await AuthFlow(agent).assertLoginFails(session);
  }

  Future<void> run(AuthSession session) async {
    await agent.runStep('Logout from profile', () async {
      await agent.tapKey(TestKeys.navProfile);
      await agent.pumpUntilIdle();
      await agent.tapKey(TestKeys.profileLogout);
      await agent.pumpUntilIdle();
      await agent.waitForElementKey(TestKeys.loginEmail);
    });

    final auth = AuthFlow(agent);
    await auth.login(session);

    await agent.runStep('Verify persistent data after re-login', () async {
      await agent.waitForEnrollmentSync();
      await agent.assertVisibleKey(TestKeys.dashboardScreen);
      await agent.tapKey(TestKeys.navProfile);
      await agent.pumpUntilIdle();
      expect(find.text(session.user.email), findsOneWidget);
    });

    await agent.runStep('Delete account', () async {
      await agent.tapKey(TestKeys.profileDeleteAccount);
      await agent.pumpUntilIdle();
      if (find.byKey(TestKeys.deleteAccountPassword).evaluate().isNotEmpty) {
        await agent.enterTextKey(
          TestKeys.deleteAccountPassword,
          session.user.password,
        );
      }
      await agent.tapKey(TestKeys.deleteAccountConfirm);
      await agent.pumpUntilIdle();
      await agent.waitForElementKey(TestKeys.loginEmail);
    });

    await auth.assertLoginFails(session);
  }
}
