import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:student_app_flutter/core/local/api_call_tracker.dart';

import 'flows/account_lifecycle_flow.dart';
import 'flows/auth_flow.dart';
import 'flows/onboarding_flow.dart';
import 'flows/study_flow.dart';
import 'helpers/app_launcher.dart';
import 'helpers/test_reporter.dart';
import 'robot/test_agent.dart';

/// Alias of [app_test.dart] — full user journey in a single drive session.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'Full journey — exam, subject, topic, progress, delete account',
    (tester) async {
      ApiCallTracker.instance.reset();
      final reporter = TestReporter(suiteName: 'Full Journey');

      await launchAppForTest(tester);

      final agent = TestAgent(tester, reporter: reporter);
      final session = await AuthFlow(agent).runSignupAndVerify();
      await OnboardingFlow(agent).completeIfNeeded();
      await StudyFlow(agent).run();
      await AccountLifecycleFlow(agent).deleteAccountOnly(session);

      reporter.printSummary();
      await reporter.writeJsonReport();
    },
  );
}
