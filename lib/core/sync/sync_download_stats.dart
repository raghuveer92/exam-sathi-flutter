import 'package:logger/logger.dart';

/// Counts entities downloaded during initial sync / manual sync for debug logging.
class SyncDownloadStats {
  int exams = 0;
  int subjects = 0;
  int topics = 0;
  int mockTests = 0;
  int questions = 0;
  int studyProgressRows = 0;
  int dailyStudyLogs = 0;

  void log(Logger logger) {
    logger.i(
      'Sync download complete — '
      'Exams: $exams, Subjects: $subjects, Topics: $topics, '
      'Mock Tests: $mockTests, Questions: $questions, '
      'Study Progress: $studyProgressRows, Daily Logs: $dailyStudyLogs',
    );
  }
}
