import '../../data/models/user_exam_model.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../local/local_store.dart';

/// Derived daily study target — never persisted.
///
/// Per exam: remaining incomplete topic hours ÷ days until target date.
/// Overall: sum of per-exam daily targets (multiple exam plans).
class DailyTargetCalculator {
  DailyTargetCalculator({
    required LocalStore store,
    required DashboardRepository dashboardRepository,
  })  : _store = store,
        _dashboardRepository = dashboardRepository;

  final LocalStore _store;
  final DashboardRepository _dashboardRepository;

  /// Sum of [calculateDailyTargetForExam] across enrolled exams.
  double calculateOverallDailyTarget(
    List<UserExamModel> myExams, {
    UserModel? user,
  }) {
    final exams = _uniqueExams(myExams, user);
    var total = 0.0;
    for (final exam in exams) {
      total += calculateDailyTargetForExam(exam);
    }
    return _roundHours(total);
  }

  double calculateDailyTargetForExam(UserExamModel exam) {
    final daysLeft = daysLeftUntilTarget(exam.examDate);
    if (daysLeft == null || daysLeft <= 0) return 0;
    final remaining = remainingHoursForExam(exam.id, exam.examId);
    if (remaining <= 0) return 0;
    return _roundHours(remaining / daysLeft);
  }

  double remainingHoursForExam(int userExamId, int examId) {
    var total = 0.0;
    final subjects = _dashboardRepository.resolveVisibleSubjects(examId);
    for (final subject in subjects) {
      total += _remainingHoursForSubject(userExamId, examId, subject.id);
    }
    if (total <= 0 && subjects.isEmpty) {
      total += _remainingHoursFromCatalogForExam(examId);
    }
    return total;
  }

  int? daysLeftUntilTarget(String? examDate) {
    if (examDate == null || examDate.isEmpty) return null;
    final parsed = DateTime.tryParse(examDate);
    if (parsed == null) return null;
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final targetDate = DateTime(parsed.year, parsed.month, parsed.day);
    return targetDate.difference(todayDate).inDays;
  }

  List<UserExamModel> _uniqueExams(List<UserExamModel> myExams, UserModel? user) {
    final seen = <int>{};
    final exams = <UserExamModel>[];
    for (final source in [myExams, user?.userExams ?? const <UserExamModel>[]]) {
      for (final exam in source) {
        if (seen.add(exam.id)) exams.add(exam);
      }
    }
    return exams;
  }

  double _remainingHoursForSubject(
    int userExamId,
    int examId,
    int subjectId,
  ) {
    final data = _store.getJson(_store.subjectDetailKey(userExamId, subjectId));
    if (data != null) {
      return _sumIncompleteTopicHours(data);
    }
    return _estimatedHoursFromSyncCatalog(subjectId);
  }

  double _sumIncompleteTopicHours(Map<String, dynamic> subjectDetail) {
    var total = 0.0;
    final chapters = subjectDetail['chapters'];
    if (chapters is! List) return 0;
    for (final chapter in chapters) {
      if (chapter is! Map) continue;
      final topics = chapter['topics'];
      if (topics is! List) continue;
      for (final topic in topics) {
        if (topic is! Map) continue;
        if (topic['isCompleted'] == true) continue;
        total += ((topic['estimatedHours'] as num?) ?? 1.0).toDouble();
      }
    }
    return total;
  }

  double _estimatedHoursFromSyncCatalog(int subjectId) {
    final catalog = _store.getJson(LocalStore.syncCatalogMasterKey);
    if (catalog == null) return 0;

    final chapters = catalog['chapters'];
    final topics = catalog['topics'];
    if (chapters is! List || topics is! List) return 0;

    final chapterIds = <int>{};
    for (final raw in chapters) {
      if (raw is! Map) continue;
      if ((raw['subjectId'] as num?)?.toInt() == subjectId &&
          raw['isActive'] != false) {
        final id = (raw['id'] as num?)?.toInt();
        if (id != null) chapterIds.add(id);
      }
    }
    if (chapterIds.isEmpty) return 0;

    var total = 0.0;
    for (final raw in topics) {
      if (raw is! Map) continue;
      if (raw['isActive'] == false) continue;
      final chapterId = (raw['chapterId'] as num?)?.toInt();
      if (chapterId == null || !chapterIds.contains(chapterId)) continue;
      total += ((raw['estimatedHours'] as num?) ?? 1.0).toDouble();
    }
    return total;
  }

  double _remainingHoursFromCatalogForExam(int examId) {
    var total = 0.0;
    for (final subject in _dashboardRepository.resolveVisibleSubjects(examId)) {
      total += _estimatedHoursFromSyncCatalog(subject.id);
    }
    return total;
  }

  double _roundHours(double hours) => (hours * 10).round() / 10.0;
}
