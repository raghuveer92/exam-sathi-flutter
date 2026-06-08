import 'dart:math' as math;

import '../../data/models/subject_detail_model.dart';
import '../../data/models/user_exam_model.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../local/local_store.dart';

/// Recomputes all derived progress from local topic/subject caches.
///
/// Dashboard percentages, exam card %, subject rows, and analytics must never
/// be trusted from the server — always rebuild from local raw data.
class ProgressRebuildService {
  ProgressRebuildService({
    required LocalStore store,
    required DashboardRepository dashboardRepository,
  })  : _store = store,
        _dashboardRepository = dashboardRepository;

  final LocalStore _store;
  final DashboardRepository _dashboardRepository;

  /// Rebuild progress for every enrolled exam + dashboard aggregates.
  Future<void> rebuildAll() async {
    final exams = await _dashboardRepository.resolveMyExamsFromCache();
    for (final exam in exams) {
      await rebuildExam(exam.examId, userExamId: exam.id);
    }
    await _rebuildDashboardAggregates();
  }

  /// Rebuild subject-progress rows and exam-card % for one exam.
  Future<void> rebuildExam(int examId, {int? userExamId}) async {
    final progressRows = <Map<String, dynamic>>[];
    var examTotal = 0;
    var examCompleted = 0;

    final enrollmentId = userExamId ??
        await _dashboardRepository.resolveUserExamIdForExam(examId);
    if (enrollmentId == null) return;

    var subjects = _dashboardRepository.resolveVisibleSubjects(examId);
    if (subjects.isEmpty) {
      final progress = _dashboardRepository.getSubjectProgressCached(examId);
      if (progress != null && progress.isNotEmpty) {
        subjects = progress.map((p) => p.toSubjectModel(examId)).toList();
      }
    }

    for (final subject in subjects) {
      final data =
          _store.getJson(_store.subjectDetailKey(enrollmentId, subject.id));
      if (data == null) continue;

      _recalculateSubjectStats(data);
      await _store.putJson(
        _store.subjectDetailKey(enrollmentId, subject.id),
        data,
      );

      final detail = SubjectDetailModel.fromJson(data);
      examTotal += detail.totalTopics;
      examCompleted += detail.completedTopics;

      var displayOrder = subject.displayOrder;
      final cached = _dashboardRepository.getSubjectProgressCached(examId);
      if (cached != null) {
        for (final row in cached) {
          if (row.subjectId == subject.id) {
            displayOrder = row.displayOrder;
            break;
          }
        }
      }

      progressRows.add({
        'subjectId': detail.subjectId,
        'subjectName': detail.subjectName,
        'iconName': detail.iconName,
        'colorCode': detail.colorCode,
        'displayOrder': displayOrder,
        'totalTopics': detail.totalTopics,
        'completedTopics': detail.completedTopics,
        'completionPercent': detail.completionPercent,
        'totalEstimatedHours': 0.0,
      });
    }

    if (progressRows.isNotEmpty) {
      await _store.putJson(_store.subjectProgressKey(examId), progressRows);
    }

    final pct = examTotal == 0
        ? 0.0
        : ((examCompleted * 1000.0 / examTotal).round() / 10.0);
    await _patchExamProgressPercent(examId, pct, userExamId: userExamId);
  }

  Future<void> _rebuildDashboardAggregates() async {
    final dashData = _store.getJson(LocalStore.dashboardKey);
    if (dashData == null) return;

    final exams = await _dashboardRepository.resolveMyExamsFromCache();
    var totalTopics = 0;
    var completedTopics = 0;

    for (final exam in exams) {
      final rows = _store.getJsonList(_store.subjectProgressKey(exam.examId));
      if (rows == null) continue;
      for (final raw in rows) {
        if (raw is! Map) continue;
        totalTopics += (raw['totalTopics'] as num?)?.toInt() ?? 0;
        completedTopics += (raw['completedTopics'] as num?)?.toInt() ?? 0;
      }
    }

    final dash = Map<String, dynamic>.from(dashData);
    final todayHours = dash['todayHours'];
    final weeklyLogs = dash['weeklyLogs'];
    final todayTopicsCompleted = dash['todayTopicsCompleted'];

    dash['totalTopics'] = totalTopics;
    dash['completedTopics'] = completedTopics;
    dash['remainingTopics'] = math.max(0, totalTopics - completedTopics);
    dash['overallCompletionPercent'] = totalTopics == 0
        ? 0.0
        : ((completedTopics * 1000.0 / totalTopics).round() / 10.0);

    UserExamModel? activeExam;
    for (final exam in exams) {
      if (exam.isActive) {
        activeExam = exam;
        break;
      }
    }
    activeExam ??= exams.isNotEmpty ? exams.first : null;
    if (activeExam != null) {
      final activeRows =
          _store.getJsonList(_store.subjectProgressKey(activeExam.examId));
      if (activeRows != null) {
        dash['subjectProgress'] = activeRows;
      }
    }

    final myExamsJson = await _dashboardRepository.getMyExamsCached();
    dash['myExams'] = myExamsJson.map((e) => e.toJson()).toList();

    if (todayHours != null) dash['todayHours'] = todayHours;
    if (weeklyLogs != null) dash['weeklyLogs'] = weeklyLogs;
    if (todayTopicsCompleted != null) {
      dash['todayTopicsCompleted'] = todayTopicsCompleted;
    }

    await _store.putJson(LocalStore.dashboardKey, dash);
    _dashboardRepository.cacheEmbeddedDashboardProgress(dash);
  }

  Future<void> _patchExamProgressPercent(
    int examId,
    double progressPercent, {
    int? userExamId,
  }) async {
    final exams = await _dashboardRepository.getMyExamsCached();
    if (exams.isEmpty) return;

    final updated = exams.map((exam) {
      final matches = userExamId != null
          ? exam.id == userExamId
          : exam.examId == examId;
      if (!matches) return exam;
      return UserExamModel(
        id: exam.id,
        examId: exam.examId,
        examName: exam.examName,
        examDate: exam.examDate,
        daysLeft: exam.daysLeft,
        totalSubjects: exam.totalSubjects,
        progressPercent: progressPercent,
        isActive: exam.isActive,
      );
    }).toList();

    await _store.putJson(
      LocalStore.myExamsKey,
      updated.map((e) => e.toJson()).toList(),
    );

    final dashData = _store.getJson(LocalStore.dashboardKey);
    if (dashData != null) {
      final dash = Map<String, dynamic>.from(dashData);
      dash['myExams'] = updated.map((e) => e.toJson()).toList();
      await _store.putJson(LocalStore.dashboardKey, dash);
    }
  }

  void _recalculateSubjectStats(Map<String, dynamic> data) {
    var totalTopics = 0;
    var completedTopics = 0;
    var totalStudyHours = 0.0;

    final chapters = data['chapters'];
    if (chapters is! List) return;

    for (final chapter in chapters) {
      if (chapter is! Map<String, dynamic>) continue;
      var chTotal = 0;
      var chCompleted = 0;

      final topics = chapter['topics'];
      if (topics is List) {
        for (final topic in topics) {
          if (topic is! Map<String, dynamic>) continue;
          chTotal++;
          totalTopics++;
          totalStudyHours +=
              ((topic['actualHours'] as num?) ?? 0).toDouble();
          if (topic['isCompleted'] == true) {
            chCompleted++;
            completedTopics++;
          }
        }
      }

      chapter['totalTopics'] = chTotal;
      chapter['completedTopics'] = chCompleted;
      chapter['completionPercent'] =
          chTotal == 0 ? 0.0 : (chCompleted * 100.0 / chTotal);
    }

    data['totalTopics'] = totalTopics;
    data['completedTopics'] = completedTopics;
    data['completionPercent'] =
        totalTopics == 0 ? 0.0 : (completedTopics * 100.0 / totalTopics);
    data['totalStudyHours'] = totalStudyHours;
  }
}
