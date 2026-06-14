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

/// Default CI / script target — one [app.main] per flutter drive session.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('ExamSaathi full E2E — auth, onboarding, study, delete account',
      (tester) async {
    ApiCallTracker.instance.reset();
    final reporter = TestReporter(suiteName: 'ExamSaathi Full Suite');
    final agent = TestAgent(tester, reporter: reporter);

    await launchAppForTest(tester);

    final auth = AuthFlow(agent);
    final session = await auth.runSignupAndVerify();

    await OnboardingFlow(agent).completeIfNeeded();
    await StudyFlow(agent).run();
    await AccountLifecycleFlow(agent).deleteAccountOnly(session);

    reporter.printSummary();
    await reporter.writeJsonReport();
  });
}

/// Convenience runner metadata exposed to CI.
class IntegrationTestMeta {
  static String get command => './scripts/run_integration_chrome.sh';
}
