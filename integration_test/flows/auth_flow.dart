import 'package:flutter_test/flutter_test.dart';

import 'package:student_app_flutter/core/testing/test_keys.dart';

import '../helpers/otp_helper.dart';
import '../helpers/test_user_generator.dart';
import '../robot/test_agent.dart';

/// Shared credentials passed between flows in a single test run.
class AuthSession {
  AuthSession(this.user);

  final TestUser user;
}

/// Registration → OTP verification → authenticated home/onboarding.
class AuthFlow {
  AuthFlow(this.agent);

  final TestAgent agent;

  Future<AuthSession> runSignupAndVerify() async {
    final user = TestUserGenerator.generate();
    late AuthSession session;

    await agent.runStep('Navigate to Sign Up', () async {
      await agent.waitForElementKey(TestKeys.loginEmail);
      await agent.tapKey(TestKeys.signUpLink);
      await agent.pumpUntilIdle();
      await agent.assertVisibleKey(TestKeys.registerSubmit);
    });

    await agent.runStep('Fill registration form', () async {
      await agent.enterTextKey(TestKeys.registerName, user.fullName);
      await agent.enterTextKey(TestKeys.registerEmail, user.email);
      await agent.enterTextKey(TestKeys.registerPassword, user.password);
    });

    await agent.runStep('Submit registration', () async {
      await agent.tapKey(TestKeys.registerSubmit);
      await agent.pumpUntilIdle();
    });

    await agent.runStep('Verify OTP screen appears', () async {
      await agent.waitForElementKey(TestKeys.otpField);
      await agent.assertVisibleKey(TestKeys.otpVerifySubmit);
    });

    await agent.runStep('Enter dev OTP and verify', () async {
      final otp = OtpHelper.getOtp(user.email);
      await agent.enterTextKey(TestKeys.otpField, otp);
      await agent.tapKey(TestKeys.otpVerifySubmit);
      await agent.pumpUntilIdle();
    });

    await agent.runStep('Assert home or onboarding reached', () async {
      final onboarding = find.byKey(TestKeys.onboardingConfirmSubmit);
      final dashboard = find.byKey(TestKeys.dashboardScreen);
      final offline = find.byKey(TestKeys.offlineSetupScreen);
      await agent.wait.waitForElement(
        find.byWidgetPredicate(
          (_) => onboarding.evaluate().isNotEmpty ||
              dashboard.evaluate().isNotEmpty ||
              offline.evaluate().isNotEmpty ||
              find.text('Choose Your Exam').evaluate().isNotEmpty,
        ),
        timeout: const Duration(seconds: 90),
      );
    });

    session = AuthSession(user);
    return session;
  }

  Future<void> login(AuthSession session) async {
    await agent.runStep('Login with credentials', () async {
      await agent.waitForElementKey(TestKeys.loginEmail);
      await agent.enterTextKey(TestKeys.loginEmail, session.user.email);
      await agent.enterTextKey(TestKeys.loginPassword, session.user.password);
      await agent.tapKey(TestKeys.loginSubmit);
      await agent.pumpUntilIdle();
    });

    await agent.runStep('Assert login success', () async {
      await agent.wait.waitForElement(
        find.byWidgetPredicate(
          (_) =>
              find.byKey(TestKeys.dashboardScreen).evaluate().isNotEmpty ||
              find.byKey(TestKeys.offlineSetupScreen).evaluate().isNotEmpty ||
              find.text('Choose Your Exam').evaluate().isNotEmpty,
        ),
        timeout: const Duration(seconds: 90),
      );
    });
  }

  Future<void> assertLoginFails(AuthSession session) async {
    await agent.runStep('Attempt login after account deletion', () async {
      await agent.waitForElementKey(TestKeys.loginEmail);
      await agent.enterTextKey(TestKeys.loginEmail, session.user.email);
      await agent.enterTextKey(TestKeys.loginPassword, session.user.password);
      await agent.tapKey(TestKeys.loginSubmit);
      await agent.pumpUntilIdle();
    });

    await agent.runStep('Assert login blocked', () async {
      await agent.waitForElementKey(TestKeys.loginEmail);
      expect(find.byKey(TestKeys.dashboardScreen), findsNothing);
    });
  }
}
