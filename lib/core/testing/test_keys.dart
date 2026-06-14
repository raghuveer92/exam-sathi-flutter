import 'package:flutter/material.dart';

/// Stable widget keys for integration / E2E automation.
/// Prefer these over hard-coded UI strings in tests.
abstract final class TestKeys {
  // ── Auth ──────────────────────────────────────────────────────────────────
  static const loginEmail = ValueKey<String>('test_login_email');
  static const loginPassword = ValueKey<String>('test_login_password');
  static const loginSubmit = ValueKey<String>('test_login_submit');
  static const signUpLink = ValueKey<String>('test_sign_up_link');

  static const registerName = ValueKey<String>('test_register_name');
  static const registerEmail = ValueKey<String>('test_register_email');
  static const registerPassword = ValueKey<String>('test_register_password');
  static const registerSubmit = ValueKey<String>('test_register_submit');

  static const otpField = ValueKey<String>('test_otp_field');
  static const otpVerifySubmit = ValueKey<String>('test_otp_verify_submit');

  // ── Onboarding ──────────────────────────────────────────────────────────────
  static ValueKey<String> examCard(int examId) =>
      ValueKey<String>('test_exam_card_$examId');
  static const examCatalogReady =
      ValueKey<String>('test_exam_catalog_ready');
  static const examSelectionInProgress =
      ValueKey<String>('test_exam_selection_in_progress');
  static const onboardingGoalStep =
      ValueKey<String>('test_onboarding_goal_step');
  static const onboardingGoalContinue =
      ValueKey<String>('test_onboarding_goal_continue');
  static const onboardingConfirmStep =
      ValueKey<String>('test_onboarding_confirm_step');
  static const onboardingConfirmSubmit =
      ValueKey<String>('test_onboarding_confirm_submit');
  static const optionalSubjectsContinue =
      ValueKey<String>('test_optional_subjects_continue');

  // ── Offline sync ────────────────────────────────────────────────────────────
  static const offlineSetupScreen =
      ValueKey<String>('test_offline_setup_screen');

  // ── Main navigation ─────────────────────────────────────────────────────────
  static const navHome = ValueKey<String>('test_nav_home');
  static const navSubjects = ValueKey<String>('test_nav_subjects');
  static const navProfile = ValueKey<String>('test_nav_profile');

  // ── Dashboard ───────────────────────────────────────────────────────────────
  static const dashboardScreen = ValueKey<String>('test_dashboard_screen');
  static const dashboardSyllabusProgress =
      ValueKey<String>('test_dashboard_syllabus_progress');

  // ── Study / subjects ────────────────────────────────────────────────────────
  static const subjectDetailScreen =
      ValueKey<String>('test_subject_detail_screen');
  static ValueKey<String> subjectRow(int subjectId) =>
      ValueKey<String>('test_subject_row_$subjectId');
  static ValueKey<String> topicTile(int topicId) =>
      ValueKey<String>('test_topic_tile_$topicId');
  static const topicSelectionPanel =
      ValueKey<String>('test_topic_selection_panel');
  static const studyHoursDisplay =
      ValueKey<String>('test_study_hours_display');
  static const studyHoursIncrement =
      ValueKey<String>('test_study_hours_increment');
  static const markTopicsCompleted =
      ValueKey<String>('test_mark_topics_completed');

  // ── Profile / account ───────────────────────────────────────────────────────
  static const profileLogout = ValueKey<String>('test_profile_logout');
  static const profileDeleteAccount =
      ValueKey<String>('test_profile_delete_account');
  static const deleteAccountConfirm =
      ValueKey<String>('test_delete_account_confirm');
  static const deleteAccountPassword =
      ValueKey<String>('test_delete_account_password');
}
