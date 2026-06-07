/// Maps backend student tables to local Hive storage keys.
///
/// Local DB is the single source of truth for UI. Sync reads/writes raw tables;
/// derived percentages are always recalculated by [ProgressRebuildService].
abstract final class LocalTables {
  // ── User / enrollment ───────────────────────────────────────────────────
  static const userProfile = 'user_profile';
  static const userExams = 'my_exams';
  static const cachedUserId = 'cached_user_id';

  // ── Raw progress (table-level sync) ───────────────────────────────────────
  /// Map keyed by topicId → study_progress row + syncStatus.
  static const topicProgress = 'table_topic_progress';

  /// Map keyed by studyDate → daily_study_logs row + syncStatus.
  static const dailyStudyLogs = 'table_daily_study_logs';

  // ── Syllabus catalog (shared master data) ─────────────────────────────────
  static const syncCatalogMaster = 'sync_catalog_master';
  static const syncCatalogAt = 'sync_catalog_at';

  // ── Denormalized views (rebuilt from raw + catalog) ─────────────────────
  static const dashboard = 'dashboard';
  static const offlineQueue = 'offline_queue';

  static String subjectProgress(int examId) => 'subject_progress_$examId';
  static String visibleSubjects(int examId) => 'visible_subjects_$examId';
  static String subjectDetail(int subjectId) => 'subject_detail_$subjectId';

  /// Standard sync metadata fields on raw records.
  static const syncStatusPending = 'PENDING';
  static const syncStatusSynced = 'SYNCED';
}
