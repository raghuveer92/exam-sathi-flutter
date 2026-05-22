import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Centralised Firebase Analytics helper.
///
/// Events fire on real Android/iOS devices in both debug and release mode.
/// In debug mode every event is also printed to the console so you can
/// verify instantly without waiting for the Firebase dashboard.
///
/// Web is excluded — Firebase Analytics web SDK is not configured for this app.
///
/// Usage (fire-and-forget):
///   `AnalyticsService.logLogin();`
class AnalyticsService {
  const AnalyticsService._();

  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  /// Observer for GoRouter — attach in AppRouter to auto-track screen_view.
  static FirebaseAnalyticsObserver get observer =>
      FirebaseAnalyticsObserver(analytics: _analytics);

  /// Analytics is enabled on all real mobile builds (debug + release).
  /// Only disabled on web (not configured).
  static bool get _enabled => !kIsWeb;

  /// Call once after Firebase.initializeApp() to explicitly enable collection
  /// and confirm the setup in the console.
  static Future<void> initialize() async {
    if (!_enabled) return;
    await _analytics.setAnalyticsCollectionEnabled(true);
    _log('Analytics collection ENABLED (${kDebugMode ? "debug" : "release"})');
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  static void _log(String msg) {
    if (kDebugMode) debugPrint('[Analytics] $msg');
  }

  // ── App lifecycle ──────────────────────────────────────────────────────────

  static Future<void> logAppOpen() async {
    if (!_enabled) return;
    _log('app_open');
    await _analytics.logAppOpen();
  }

  // ── Auth ───────────────────────────────────────────────────────────────────

  static Future<void> logLogin({String method = 'email'}) async {
    if (!_enabled) return;
    _log('login method=$method');
    await _analytics.logLogin(loginMethod: method);
  }

  static Future<void> logSignUp({String method = 'email'}) async {
    if (!_enabled) return;
    _log('sign_up method=$method');
    await _analytics.logSignUp(signUpMethod: method);
  }

  static Future<void> logLogout() async {
    if (!_enabled) return;
    _log('logout');
    await _analytics.logEvent(name: 'logout');
  }

  // ── Onboarding ─────────────────────────────────────────────────────────────

  static Future<void> logExamSelected({
    required int examId,
    required String examName,
  }) async {
    if (!_enabled) return;
    _log('exam_selected id=$examId name=$examName');
    await _analytics.logEvent(
      name: 'exam_selected',
      parameters: {'exam_id': examId, 'exam_name': examName},
    );
  }

  static Future<void> logExamGoalSet({
    required String examDate,
    required double dailyTargetHours,
  }) async {
    if (!_enabled) return;
    _log('exam_goal_set date=$examDate daily=${dailyTargetHours}h');
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
    _log('dashboard_viewed');
    await _analytics.logEvent(name: 'dashboard_viewed');
  }

  static Future<void> logStudyGoalUpdated({
    required double dailyTargetHours,
  }) async {
    if (!_enabled) return;
    _log('study_goal_updated daily=${dailyTargetHours}h');
    await _analytics.logEvent(
      name: 'study_goal_updated',
      parameters: {'daily_target_hours': dailyTargetHours},
    );
  }

  // ── Subjects ───────────────────────────────────────────────────────────────

  static Future<void> logSubjectOpened({
    required int subjectId,
    required String subjectName,
  }) async {
    if (!_enabled) return;
    _log('subject_opened id=$subjectId name=$subjectName');
    await _analytics.logEvent(
      name: 'subject_opened',
      parameters: {'subject_id': subjectId, 'subject_name': subjectName},
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
    _log('topic_completed "$topicName" in "$subjectName" (${actualHours}h)');
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
    _log('study_hours_added ${hours}h in "$subjectName"');
    await _analytics.logEvent(
      name: 'study_hours_added',
      parameters: {'hours': hours, 'subject_name': subjectName},
    );
  }

  // ── Screen ─────────────────────────────────────────────────────────────────

  static Future<void> logScreenView({
    required String screenName,
    String? screenClass,
  }) async {
    if (!_enabled) return;
    _log('screen_view $screenName');
    await _analytics.logScreenView(
      screenName: screenName,
      screenClass: screenClass ?? screenName,
    );
  }
}
