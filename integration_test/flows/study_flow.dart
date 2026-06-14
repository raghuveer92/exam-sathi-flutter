import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:student_app_flutter/core/local/api_call_tracker.dart';
import 'package:student_app_flutter/core/testing/test_keys.dart';

import '../helpers/sync_helper.dart';
import '../robot/test_agent.dart';

/// Dashboard → subject → topic → study hours → mark complete → verify dashboard.
class StudyFlow {
  StudyFlow(this.agent);

  final TestAgent agent;

  Finder get _subjectRows => find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('test_subject_row_'),
      );

  Finder get _topicTiles => find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('test_topic_tile_'),
      );

  Future<void> run() async {
    await agent.waitForEnrollmentSync();

    await agent.runStep('Open Subjects tab', () async {
      await agent.waitForElementKey(TestKeys.dashboardScreen);
      await agent.tapKey(TestKeys.navSubjects);
      await agent.pumpUntilIdle();
      await agent.wait.waitForElement(
        find.text('Subjects'),
        timeout: const Duration(seconds: 30),
      );
    });

    await agent.runStep('Select first subject', () async {
      await agent.wait.waitForElement(_subjectRows, timeout: const Duration(seconds: 60));
      await agent.scrollUntilVisible(_subjectRows.first);
      await agent.tap(_subjectRows.first);
      await agent.pumpUntilIdle();
      await agent.waitForElementKey(
        TestKeys.subjectDetailScreen,
        timeout: const Duration(seconds: 60),
      );
      await agent.wait.waitForElement(
        find.text('Chapter'),
        timeout: const Duration(seconds: 30),
      );
      expect(find.textContaining('Topics not downloaded'), findsNothing);
    });

    await agent.runStep('Verify chapters and topics loaded', () async {
      expect(find.textContaining('Topics not downloaded'), findsNothing);
      await agent.wait.waitForElement(
        find.text('Chapter'),
        timeout: const Duration(seconds: 30),
      );
      await agent.wait.waitForElement(
        find.textContaining('Topics ('),
        timeout: const Duration(seconds: 30),
      );
      expect(_topicTiles, findsWidgets);
    });

    await agent.runStep('Select first topic', () async {
      final firstTopic = _topicTiles.first;
      await agent.scrollUntilVisible(firstTopic);
      await agent.tap(firstTopic);
      await agent.pumpUntilIdle();
      await agent.waitForElementKey(TestKeys.studyHoursIncrement);
    });

    await agent.runStep('Add study hours with + button', () async {
      ApiCallTracker.instance.reset();
      await agent.tapKey(TestKeys.studyHoursIncrement);
      await agent.pumpUntilIdle();
      await agent.wait.waitForElement(
        find.byWidgetPredicate(
          (w) =>
              w.key == TestKeys.studyHoursDisplay &&
              w is Text &&
              w.data == '1h',
        ),
        timeout: const Duration(seconds: 15),
      );
    });

    await agent.runStep('Mark topic complete', () async {
      await agent.tapKey(TestKeys.markTopicsCompleted);
      await agent.pumpUntilIdle();
      // Selection panel closes on success; snackbar text is a secondary signal.
      await agent.wait.waitForElementToDisappear(
        find.byKey(TestKeys.topicSelectionPanel),
        timeout: const Duration(seconds: 60),
      );
    });

    await agent.runStep('Return to dashboard', () async {
      await agent.tapKey(TestKeys.navHome);
      await agent.pumpUntilIdle();
      await agent.waitForElementKey(
        TestKeys.dashboardScreen,
        timeout: const Duration(seconds: 60),
      );
    });

    await assertDashboardProgressUpdated();
  }

  Future<void> assertDashboardProgressUpdated() async {
    await agent.runStep('Assert dashboard progress updated', () async {
      final progressFinder = find.byKey(TestKeys.dashboardSyllabusProgress);
      await agent.wait.waitForElement(
        find.byWidgetPredicate(
          (_) {
            if (progressFinder.evaluate().isEmpty) return false;
            final text =
                (agent.tester.widget<Text>(progressFinder).data ?? '');
            final match = RegExp(r'(\d+) of (\d+) topics').firstMatch(text);
            if (match == null) return false;
            final completed = int.parse(match.group(1)!);
            return completed > 0;
          },
        ),
        timeout: const Duration(seconds: 90),
      );

      final textWidget = agent.tester.widget<Text>(progressFinder);
      final match =
          RegExp(r'(\d+) of (\d+) topics').firstMatch(textWidget.data ?? '');
      expect(match, isNotNull);

      final completed = int.parse(match!.group(1)!);
      final total = int.parse(match.group(2)!);
      expect(completed, greaterThan(0));
      expect(total, greaterThan(0));
      expect(completed, lessThanOrEqualTo(total));
    });
  }
}
