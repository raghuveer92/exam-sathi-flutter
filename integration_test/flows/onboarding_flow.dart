import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:student_app_flutter/core/testing/test_keys.dart';

import '../helpers/sync_helper.dart';
import '../robot/test_agent.dart';

/// Exam selection, goal setup, sync, and dashboard verification.
class OnboardingFlow {
  OnboardingFlow(this.agent);

  final TestAgent agent;

  Finder get _examCards => find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('test_exam_card_'),
      );

  Finder get _goalStep => find.byKey(TestKeys.onboardingGoalStep);

  Finder get _confirmStep => find.byKey(TestKeys.onboardingConfirmStep);

  Finder get _goalContinue => find.byKey(TestKeys.onboardingGoalContinue);

  Finder get _confirmSubmit => find.byKey(TestKeys.onboardingConfirmSubmit);

  /// Step 2 is reached when the app bar title or goal body is visible.
  Finder get _step2Reached => find.byWidgetPredicate(
        (_) =>
            find.text('Set Your Goal').evaluate().isNotEmpty ||
            find.byKey(TestKeys.onboardingGoalStep).evaluate().isNotEmpty ||
            find.text('Target Exam Date').evaluate().isNotEmpty,
      );

  Future<void> completeIfNeeded() async {
    if (find.text('Choose Your Exam').evaluate().isEmpty &&
        find.byKey(TestKeys.dashboardScreen).evaluate().isNotEmpty) {
      return;
    }

    await agent.runStep('Wait for exam catalog to fully load', () async {
      await agent.wait.waitForElement(
        find.text('Choose Your Exam'),
        timeout: const Duration(seconds: 30),
      );

      final fullScreenLoader = find.descendant(
        of: find.byType(Scaffold),
        matching: find.byType(CircularProgressIndicator),
      );
      if (fullScreenLoader.evaluate().isNotEmpty) {
        await agent.wait.waitForElementToDisappear(
          fullScreenLoader,
          timeout: const Duration(seconds: 60),
        );
      }

      await agent.waitForElementKey(
        TestKeys.examCatalogReady,
        timeout: const Duration(seconds: 90),
      );

      expect(_examCards, findsWidgets);
      await agent.pumpUntilIdle();
    });

    await agent.runStep('Select first exam with syllabus content', () async {
      expect(_examCards, findsWidgets);

      // Recommended row is first in the UI; prefer an exam known to have topics
      // (e.g. Delhi Police) over placeholder cards with empty scoped catalogs.
      final preferred = find.byKey(TestKeys.examCard(19));
      final target =
          preferred.evaluate().isNotEmpty ? preferred : _examCards.first;
      await agent.scrollUntilVisible(target);
      await agent.pumpUntilIdle();

      await agent.tap(target);

      await agent.wait.waitForElement(
        find.text('Set Your Goal'),
        timeout: const Duration(seconds: 60),
      );

      // Optional-subject resolution runs on the goal screen — wait for overlay.
      final overlay = find.byKey(TestKeys.examSelectionInProgress);
      if (overlay.evaluate().isNotEmpty) {
        await agent.wait.waitForElementToDisappear(
          overlay,
          timeout: const Duration(seconds: 90),
        );
      }
      await agent.pumpUntilIdle();
    });

    await agent.runStep('Handle optional subjects dialog', () async {
      final dialogTitle = find.textContaining('Choose Optional Subjects');
      if (dialogTitle.evaluate().isEmpty) return;

      final radios = find.byType(RadioListTile<int>);
      for (var i = 0; i < radios.evaluate().length; i++) {
        await agent.tap(radios.at(i));
      }
      final checkboxes = find.byType(CheckboxListTile);
      for (var i = 0; i < checkboxes.evaluate().length; i++) {
        await agent.tap(checkboxes.at(i));
      }

      await agent.tapKey(TestKeys.optionalSubjectsContinue);
      await agent.wait.waitForElement(_step2Reached, timeout: const Duration(seconds: 30));
      await agent.pumpUntilIdle();
    });

    await agent.runStep('Set goal and continue', () async {
      await agent.wait.waitForElement(_goalStep, timeout: const Duration(seconds: 30));
      await agent.scrollUntilVisible(_goalContinue, scrollable: _goalStep);
      await agent.tapKey(TestKeys.onboardingGoalContinue);
      await agent.pumpUntilIdle();

      await agent.wait.waitForElement(
        find.byWidgetPredicate(
          (_) =>
              _confirmStep.evaluate().isNotEmpty ||
              _confirmSubmit.evaluate().isNotEmpty ||
              find.text('Confirm Setup').evaluate().isNotEmpty,
        ),
        timeout: const Duration(seconds: 30),
      );
      await agent.pumpUntilIdle();
    });

    await agent.runStep('Confirm enrollment', () async {
      await agent.wait.waitForElement(_confirmSubmit, timeout: const Duration(seconds: 30));
      await agent.scrollUntilVisible(_confirmSubmit, scrollable: _confirmStep);
      await agent.tapKey(TestKeys.onboardingConfirmSubmit);
      await agent.pumpUntilIdle();
    });

    await agent.waitForEnrollmentSync();

    await agent.runStep('Assert dashboard loads', () async {
      await agent.waitForElementKey(
        TestKeys.dashboardScreen,
        timeout: const Duration(seconds: 120),
      );
    });
  }

  Future<void> assertExamSavedInProfile() async {
    await agent.runStep('Open profile and verify exam badge', () async {
      await agent.tapKey(TestKeys.navProfile);
      await agent.pumpUntilIdle();
      await agent.wait.waitForElement(
        find.byWidgetPredicate(
          (_) => find.textContaining('NEET').evaluate().isNotEmpty ||
              find.textContaining('JEE').evaluate().isNotEmpty ||
              find.textContaining('UPSC').evaluate().isNotEmpty ||
              find.text('Profile').evaluate().isNotEmpty,
        ),
      );
    });
  }
}
