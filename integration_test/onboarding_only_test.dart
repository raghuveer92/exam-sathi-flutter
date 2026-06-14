import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:student_app_flutter/core/local/api_call_tracker.dart';

import 'flows/auth_flow.dart';
import 'flows/onboarding_flow.dart';
import 'helpers/app_launcher.dart';
import 'helpers/test_reporter.dart';
import 'robot/test_agent.dart';

/// Fast regression: signup + onboarding only (single app launch).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('Onboarding — exam selection through dashboard', (tester) async {
    ApiCallTracker.instance.reset();
    final reporter = TestReporter(suiteName: 'Onboarding Only');

    await launchAppForTest(tester);

    final agent = TestAgent(tester, reporter: reporter);
    await AuthFlow(agent).runSignupAndVerify();
    await OnboardingFlow(agent).completeIfNeeded();

    reporter.printSummary();
    await reporter.writeJsonReport();
  });
}
