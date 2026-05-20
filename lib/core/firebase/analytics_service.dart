import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Centralised Firebase Analytics helper.
///
/// All methods are no-ops in debug mode and on web (mobile-only for now).
/// Call the static methods from screens / blocs as fire-and-forget:
///   `AnalyticsService.logLogin();`
class AnalyticsService {
  const AnalyticsService._();

  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  /// Observer for GoRouter — pass to routerConfig if needed in future.
  static FirebaseAnalyticsObserver get observer =>
      FirebaseAnalyticsObserver(analytics: _analytics);

  static bool get _enabled => !kIsWeb && !kDebugMode;

  // ── Auth ───────────────────────────────────────────────────────────────────

  static Future<void> logLogin({String method = 'email'}) async {
    if (!_enabled) return;
    await _analytics.logLogin(loginMethod: method);
  }

  static Future<void> logSignUp({String method = 'email'}) async {
    if (!_enabled) return;
    await _analytics.logSignUp(signUpMethod: method);
  }

  static Future<void> logLogout() async {
    if (!_enabled) return;
    await _analytics.logEvent(name: 'logout');
  }

  // ── Onboarding ─────────────────────────────────────────────────────────────

  static Future<void> logExamSelected({
    required int examId,
    required String examName,
  }) async {
    if (!_enabled) return;
    await _analytics.logEvent(
      name: 'exam_selected',
      parameters: {
        'exam_id': examId,
        'exam_name': examName,
      },
    );
  }

  static Future<void> logExamGoalSet({
    required String examDate,
    required double dailyTargetHours,
  }) async {
    if (!_enabled) return;
    await _analytics.logEvent(
      name: 'exam_goal_set',
      parameters: {
        'exam_date': examDate,
        'daily_target_hours': dailyTargetHours,
      },
    );
  }

  // ── Dashboard ──────────────────────────────────────────────────────────────

  static Future<void> logDashboardViewed() async {
    if (!_enabled) return;
    await _analytics.logEvent(name: 'dashboard_viewed');
  }

  static Future<void> logStudyGoalUpdated({
    required double dailyTargetHours,
  }) async {
    if (!_enabled) return;
    await _analytics.logEvent(
      name: 'study_goal_updated',
      parameters: {'daily_target_hours': dailyTargetHours},
    );
  }

  // ── Progress ───────────────────────────────────────────────────────────────

  static Future<void> logTopicCompleted({
    required int topicId,
    required String topicName,
    required String subjectName,
    required double actualHours,
  }) async {
    if (!_enabled) return;
    await _analytics.logEvent(
      name: 'topic_completed',
      parameters: {
        'topic_id': topicId,
        'topic_name': topicName,
        'subject_name': subjectName,
        'actual_hours': actualHours,
      },
    );
  }

  static Future<void> logStudyHoursAdded({
    required double hours,
    required String subjectName,
  }) async {
    if (!_enabled) return;
    await _analytics.logEvent(
      name: 'study_hours_added',
      parameters: {
        'hours': hours,
        'subject_name': subjectName,
      },
    );
  }

  // ── Screen ─────────────────────────────────────────────────────────────────

  static Future<void> logScreenView({
    required String screenName,
    String? screenClass,
  }) async {
    if (!_enabled) return;
    await _analytics.logScreenView(
      screenName: screenName,
      screenClass: screenClass ?? screenName,
    );
  }
}
