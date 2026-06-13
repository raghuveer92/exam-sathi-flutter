/// API base URL and endpoint constants.
class ApiEndpoints {
  ApiEndpoints._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://exam-sathi.onrender.com/api/v1',
  );

  // Auth
  static const String register = '/auth/register';
  static const String login = '/auth/login';
  static const String googleSignIn = '/auth/google';
  static const String verifyEmailOtp = '/auth/verify-email-otp';
  static const String resendEmailOtp = '/auth/resend-email-otp';
  static const String forgotPassword = '/auth/forgot-password';
  static const String verifyForgotPasswordOtp = '/auth/verify-forgot-password-otp';
  static const String resetPassword = '/auth/reset-password';

  // Student
  static const String me = '/student/me';
  static const String dashboard = '/student/dashboard';
  static const String myExams = '/student/my-exams';
  static const String examGoal = '/student/exam-goal';
  static const String studyHours = '/student/study-hours';
  static String selectExam(int examId) => '/student/exam/$examId';
  static String examSubjectGroups(int examId) => '/student/exams/$examId/subject-groups';
  static String myExamDate(int userExamId) => '/student/my-exams/$userExamId/date';
  static String setActiveMyExam(int userExamId) => '/student/my-exams/$userExamId/active';
  static String deleteMyExam(int userExamId) => '/student/my-exams/$userExamId';
  static String subjectSelections(int userExamId) => '/student/my-exams/$userExamId/subject-selections';

  // Exams
  static const String exams = '/exams';
  static String examById(int id) => '/exams/$id';

  // Exam catalog
  static const String examCatalog = '/exam-catalog';
  static const String examCatalogSearch = '/exam-catalog/search';
  static String examsByCategory(int categoryId) =>
      '/exam-catalog/categories/$categoryId/exams';
  static const String enrollExam = '/student/my-exams/enroll';

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

  // Mock Tests
  static String mockTestTopicInfo(int topicId) => '/mock-tests/topics/$topicId/info';
  static String mockTestStart(int topicId) => '/mock-tests/topics/$topicId/start';
  static String mockTestAttempts(int topicId) => '/mock-tests/topics/$topicId/attempts';
  static String mockTestSubmit(int attemptId) => '/mock-tests/attempts/$attemptId/submit';
  static String mockTestAttempt(int attemptId) => '/mock-tests/attempts/$attemptId';
  static const String mockTestPerformance = '/mock-tests/performance';

  // Sync (offline-first)
  static const String syncCatalog = '/sync/catalog';
  static const String syncBundle = '/sync/bundle';
  static const String syncPush = '/sync/push';
}
