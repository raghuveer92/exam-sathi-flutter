/// Sync queue item lifecycle — local DB is source of truth; server is backup.
abstract final class SyncQueueStatus {
  static const pending = 'PENDING';
  static const syncing = 'SYNCING';
  static const completed = 'COMPLETED';
  static const failed = 'FAILED';

  static bool isProcessable(String? status) =>
      status == pending || status == failed;
}

/// High-level operation labels stored on each queue row.
abstract final class SyncOperationType {
  static const topicProgressUpdate = 'TOPIC_PROGRESS_UPDATE';
  static const topicComplete = 'TOPIC_COMPLETE';
  static const examUpdate = 'EXAM_UPDATE';
  static const profileUpdate = 'PROFILE_UPDATE';
  static const studyLog = 'STUDY_LOG';
  static const submitTest = 'SUBMIT_TEST';

  static String forAction(String action) => switch (action) {
        'COMPLETE_TOPIC' => topicComplete,
        'ADD_STUDY_HOURS' || 'TOPIC_PROGRESS' => topicProgressUpdate,
        'LOG_STUDY_HOURS' || 'LOG_STUDY' => studyLog,
        'SET_ACTIVE_EXAM' || 'UPDATE_EXAM_DATE' => examUpdate,
        'SUBMIT_TEST' => submitTest,
        _ => action,
      };
}
