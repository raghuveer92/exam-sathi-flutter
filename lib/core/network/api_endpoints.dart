/// API base URL and endpoint constants.
class ApiEndpoints {
  ApiEndpoints._();

  static const String baseUrl = 'https://exam-sathi.onrender.com/api/v1';

  // Auth
  static const String register = '/auth/register';
  static const String login = '/auth/login';

  // Student
  static const String me = '/student/me';
  static const String dashboard = '/student/dashboard';
  static const String examGoal = '/student/exam-goal';
  static const String studyHours = '/student/study-hours';
  static String selectExam(int examId) => '/student/exam/$examId';

  // Exams
  static const String exams = '/exams';
  static String examById(int id) => '/exams/$id';

  // Subjects
  static String subjectsByExam(int examId) => '/subjects/exam/$examId';
  static String subjectById(int id) => '/subjects/$id';

  // Syllabus
  static String chaptersBySubject(int subjectId) => '/syllabus/chapters/subject/$subjectId';
  static String chapterById(int id) => '/syllabus/chapters/$id';
  static String topicsByChapter(int chapterId) => '/syllabus/topics/chapter/$chapterId';

  // Progress
  static const String updateProgress = '/progress/topic';
  static const String logStudy = '/progress/log';
  static const String weeklyLogs = '/progress/weekly';
  static String subjectDetail(int subjectId) => '/progress/subject/$subjectId';
  static String subjectProgress(int examId) => '/progress/subjects/$examId';
}
