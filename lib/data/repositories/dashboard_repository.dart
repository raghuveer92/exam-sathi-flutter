import 'dart:math' as math;

import '../models/dashboard_model.dart';
import '../models/subject_detail_model.dart';
import '../models/exam_subject_group_model.dart';
import '../models/exam_model.dart';
import '../models/subject_model.dart';
import '../models/subject_progress_model.dart';
import '../models/user_exam_model.dart';
import '../models/user_model.dart';
import '../../core/local/api_call_tracker.dart';
import '../../core/local/local_store.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/connectivity_helper.dart';
import '../../core/sync/offline_queue_service.dart';

/// Formats a DateTime to YYYY-MM-DD using local year/month/day fields.
String _fmtLocalDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Local-only grouping for subjects screen.
class ExamSubjectsCacheGroup {
  final UserExamModel exam;
  final List<SubjectModel> subjects;
  final List<SubjectProgressModel> progressRows;

  const ExamSubjectsCacheGroup({
    required this.exam,
    required this.subjects,
    required this.progressRows,
  });
}

class DashboardRepository {
  final ApiClient _client;
  final LocalStore _store;
  final OfflineQueueService _offlineQueue;

  DashboardRepository({
    required ApiClient client,
    required LocalStore store,
    required OfflineQueueService offlineQueue,
  })  : _client = client,
        _store = store,
        _offlineQueue = offlineQueue;

  // ── Cache-first reads ─────────────────────────────────────────────────────

  Future<DashboardModel?> getDashboardCached() async {
    final data = _store.getJson(LocalStore.dashboardKey);
    if (data == null) return null;
    final hydrated = _hydrateDashboardMap(data);
    if (hydrated != data) {
      await _store.putJson(LocalStore.dashboardKey, hydrated);
    }
    return DashboardModel.fromJson(hydrated);
  }

  /// Reconcile daily target + myExams from profile and sync bundle caches.
  Map<String, dynamic> _hydrateDashboardMap(Map<String, dynamic> data) {
    return _mergeDailyTargetIntoDashboard(
      data,
      bundleMyExams: _store.getJsonList(LocalStore.myExamsKey),
      profileUser: _store.getJson(LocalStore.userProfileKey),
    );
  }

  /// Patch dashboard user daily target from cached profile after login/sync.
  Future<void> syncDailyTargetFromProfile() async {
    final dash = _store.getJson(LocalStore.dashboardKey);
    if (dash == null) return;
    final merged = _mergeDailyTargetIntoDashboard(
      dash,
      bundleMyExams: _store.getJsonList(LocalStore.myExamsKey),
      profileUser: _store.getJson(LocalStore.userProfileKey),
    );
    await _store.putJson(LocalStore.dashboardKey, merged);
    final user = merged['user'];
    if (user != null) {
      await _store.putJson(LocalStore.userProfileKey, user);
    }
  }

  /// Persist server dashboard without wiping a known local daily target.
  Future<void> storeSyncedDashboard(
    Map<String, dynamic> remote, {
    List<dynamic>? bundleMyExams,
    Map<String, dynamic>? profileUser,
  }) async {
    final localDash = _store.getJson(LocalStore.dashboardKey);
    var merged = _mergeDailyTargetIntoDashboard(
      remote,
      bundleMyExams: bundleMyExams ?? _store.getJsonList(LocalStore.myExamsKey),
      profileUser: profileUser ?? _store.getJson(LocalStore.userProfileKey),
    );
    merged = _mergeStudyProgressIntoDashboard(merged, localDash);
    await _store.putJson(LocalStore.dashboardKey, merged);
    cacheEmbeddedDashboardProgress(merged);
    final user = merged['user'];
    if (user != null) {
      await _store.putJson(LocalStore.userProfileKey, user);
    }
  }

  /// Merge exam-level subject progress rows — keep higher completed counts.
  List<Map<String, dynamic>> mergeSubjectProgressLists(
    List<dynamic>? local,
    List<dynamic> remote,
  ) {
    final bySubject = <int, Map<String, dynamic>>{};

    void ingest(List<dynamic>? rows) {
      if (rows == null) return;
      for (final raw in rows) {
        if (raw is! Map<String, dynamic>) continue;
        final subjectId = (raw['subjectId'] as num?)?.toInt();
        if (subjectId == null) continue;
        final completed = ((raw['completedTopics'] as num?) ?? 0).toInt();
        final existing = bySubject[subjectId];
        if (existing == null) {
          bySubject[subjectId] = Map<String, dynamic>.from(raw);
          continue;
        }
        final bestCompleted = math.max(
          ((existing['completedTopics'] as num?) ?? 0).toInt(),
          completed,
        );
        if (bestCompleted > ((existing['completedTopics'] as num?) ?? 0).toInt()) {
          existing['completedTopics'] = bestCompleted;
          existing['completionPercent'] = raw['completionPercent'];
        }
      }
    }

    ingest(local);
    ingest(remote);
    return bySubject.values.toList();
  }

  Map<String, dynamic> _mergeStudyProgressIntoDashboard(
    Map<String, dynamic> remote,
    Map<String, dynamic>? local,
  ) {
    if (local == null) return remote;

    final merged = Map<String, dynamic>.from(remote);
    merged['todayHours'] = math.max(
      ((merged['todayHours'] as num?) ?? 0).toDouble(),
      ((local['todayHours'] as num?) ?? 0).toDouble(),
    );

    final remoteCompleted = ((merged['completedTopics'] as num?) ?? 0).toInt();
    final localCompleted = ((local['completedTopics'] as num?) ?? 0).toInt();
    if (localCompleted > remoteCompleted) {
      merged['completedTopics'] = localCompleted;
      final total = ((merged['totalTopics'] as num?) ?? 0).toInt();
      merged['remainingTopics'] = math.max(0, total - localCompleted);
      merged['overallCompletionPercent'] =
          total == 0 ? 0.0 : (localCompleted * 100.0 / total);
    }

    merged['weeklyLogs'] = _mergeWeeklyLogs(
      merged['weeklyLogs'] as List<dynamic>?,
      local['weeklyLogs'] as List<dynamic>?,
    );

    merged['subjectProgress'] = mergeSubjectProgressLists(
      local['subjectProgress'] as List<dynamic>?,
      merged['subjectProgress'] as List<dynamic>? ?? const [],
    );

    return merged;
  }

  List<Map<String, dynamic>> _mergeWeeklyLogs(
    List<dynamic>? remote,
    List<dynamic>? local,
  ) {
    final byDate = <String, Map<String, dynamic>>{};

    void ingest(List<dynamic>? rows) {
      if (rows == null) return;
      for (final raw in rows) {
        if (raw is! Map) continue;
        final row = Map<String, dynamic>.from(raw);
        final date = row['studyDate'] as String?;
        if (date == null) continue;
        final existing = byDate[date];
        if (existing == null) {
          byDate[date] = row;
          continue;
        }
        existing['hoursStudied'] = math.max(
          ((existing['hoursStudied'] as num?) ?? 0).toDouble(),
          ((row['hoursStudied'] as num?) ?? 0).toDouble(),
        );
        existing['topicsCompleted'] = math.max(
          ((existing['topicsCompleted'] as num?) ?? 0).toInt(),
          ((row['topicsCompleted'] as num?) ?? 0).toInt(),
        );
      }
    }

    ingest(remote);
    ingest(local);
    return byDate.values.toList();
  }

  Map<String, dynamic> _mergeDailyTargetIntoDashboard(
    Map<String, dynamic> remote, {
    List<dynamic>? bundleMyExams,
    Map<String, dynamic>? profileUser,
  }) {
    final merged = Map<String, dynamic>.from(remote);
    final local = _store.getJson(LocalStore.dashboardKey);
    final remoteUser = merged['user'];
    if (remoteUser is! Map<String, dynamic>) return merged;

    final user = Map<String, dynamic>.from(remoteUser);
    final remoteDaily = (user['dailyTargetHours'] as num?)?.toDouble();
    final localUser = local?['user'];
    final localDaily = localUser is Map<String, dynamic>
        ? (localUser['dailyTargetHours'] as num?)?.toDouble()
        : null;
    final profileDaily = profileUser is Map<String, dynamic>
        ? (profileUser['dailyTargetHours'] as num?)?.toDouble()
        : null;

    final examMaps = _collectExamMaps(
      dashboard: merged,
      bundleMyExams: bundleMyExams,
      profileUser: profileUser,
    );
    if (examMaps.isNotEmpty) {
      merged['myExams'] = examMaps;
    }

    double? resolvedDaily;
    if (remoteDaily != null && remoteDaily > 0) {
      resolvedDaily = remoteDaily;
    } else if (profileDaily != null && profileDaily > 0) {
      resolvedDaily = profileDaily;
    } else if (localDaily != null && localDaily > 0) {
      resolvedDaily = localDaily;
    } else {
      resolvedDaily = _dailyTargetFromMyExams(
        examMaps,
        (user['activeUserExamId'] as num?)?.toInt(),
      );
    }

    if (resolvedDaily != null && resolvedDaily > 0) {
      user['dailyTargetHours'] = resolvedDaily;
      user['weeklyTargetHours'] =
          (user['weeklyTargetHours'] as num?)?.toDouble() ??
              (profileUser?['weeklyTargetHours'] as num?)?.toDouble() ??
              (resolvedDaily * 7 * 10).round() / 10.0;
    }

    if (examMaps.isNotEmpty) {
      user['userExams'] = _enrichUserExamsFromExamMaps(
        user['userExams'] as List<dynamic>?,
        examMaps,
      );
    }

    merged['user'] = user;
    return merged;
  }

  List<Map<String, dynamic>> _enrichUserExamsFromExamMaps(
    List<dynamic>? userExams,
    List<Map<String, dynamic>> examMaps,
  ) {
    final byId = {
      for (final exam in examMaps)
        if ((exam['id'] as num?)?.toInt() case final id?) id: exam,
    };

    if (userExams == null || userExams.isEmpty) {
      return examMaps.map((e) => Map<String, dynamic>.from(e)).toList();
    }

    final enriched = <Map<String, dynamic>>[];
    for (final raw in userExams) {
      if (raw is! Map<String, dynamic>) continue;
      final copy = Map<String, dynamic>.from(raw);
      final id = (copy['id'] as num?)?.toInt();
      final source = id != null ? byId[id] : null;
      if (source != null) {
        for (final key in [
          'dailyTargetHours',
          'weeklyTargetHours',
          'isActive',
          'examDate',
        ]) {
          final value = source[key];
          if (value != null) copy[key] = value;
        }
      }
      enriched.add(copy);
    }
    return enriched;
  }

  List<Map<String, dynamic>> _collectExamMaps({
    Map<String, dynamic>? dashboard,
    List<dynamic>? bundleMyExams,
    Map<String, dynamic>? profileUser,
  }) {
    final byId = <int, Map<String, dynamic>>{};

    void addAll(List<dynamic>? list) {
      if (list == null) return;
      for (final raw in list) {
        if (raw is! Map<String, dynamic>) continue;
        final id = (raw['id'] as num?)?.toInt();
        if (id == null) continue;
        final existing = byId[id];
        if (existing == null) {
          byId[id] = Map<String, dynamic>.from(raw);
          continue;
        }
        final merged = Map<String, dynamic>.from(existing);
        for (final entry in raw.entries) {
          final value = entry.value;
          if (value == null) continue;
          if (entry.key == 'dailyTargetHours' ||
              entry.key == 'weeklyTargetHours' ||
              entry.key == 'isActive' ||
              entry.key == 'examDate') {
            merged[entry.key] = value;
          } else if (!merged.containsKey(entry.key) || merged[entry.key] == null) {
            merged[entry.key] = value;
          }
        }
        byId[id] = merged;
      }
    }

    final dashUser = dashboard?['user'];
    if (dashUser is Map<String, dynamic>) {
      addAll(dashUser['userExams'] as List<dynamic>?);
    }
    if (profileUser != null) {
      addAll(profileUser['userExams'] as List<dynamic>?);
    }
    addAll(dashboard?['myExams'] as List<dynamic>?);
    addAll(bundleMyExams);
    addAll(_store.getJsonList(LocalStore.myExamsKey));

    return byId.values.toList();
  }

  double? _dailyTargetFromMyExams(
    List<Map<String, dynamic>> exams,
    int? activeUserExamId,
  ) {
    if (exams.isEmpty) return null;

    Map<String, dynamic>? activeExam;
    for (final exam in exams) {
      final id = (exam['id'] as num?)?.toInt();
      if (activeUserExamId != null && id == activeUserExamId) {
        activeExam = exam;
        break;
      }
      if (activeExam == null && exam['isActive'] == true) {
        activeExam = exam;
      }
    }

    final candidates = [
      if (activeExam != null) activeExam,
      ...exams,
    ];

    for (final exam in candidates) {
      final hours = (exam['dailyTargetHours'] as num?)?.toDouble();
      if (hours != null && hours > 0) return hours;
    }
    return null;
  }

  /// Keeps dashboard + subject-progress caches in sync after local topic/hour edits.
  Future<void> applyLocalProgressUpdate({
    required SubjectDetailModel subjectDetail,
    required bool wasCompleted,
    required bool isCompleted,
    required double studyHoursDelta,
    required String studyDate,
  }) async {
    final dashData = _store.getJson(LocalStore.dashboardKey);
    if (dashData == null) return;

    final dash = Map<String, dynamic>.from(dashData);
    final user = dash['user'];
    if (user is! Map<String, dynamic>) return;

    final examId = await _resolveExamIdForProgress(user);
    if (examId == null) return;

    final today = _fmtLocalDate(DateTime.now());
    final newlyCompleted = isCompleted && !wasCompleted;

    if (studyDate == today && studyHoursDelta != 0) {
      dash['todayHours'] = math.max(
        0.0,
        ((dash['todayHours'] as num?) ?? 0).toDouble() + studyHoursDelta,
      );
    }

    if (newlyCompleted) {
      dash['todayTopicsCompleted'] =
          ((dash['todayTopicsCompleted'] as num?) ?? 0).toInt() + 1;
    }

    if (studyHoursDelta != 0 || newlyCompleted) {
      _patchWeeklyLog(
        dash,
        studyDate,
        studyHoursDelta,
        newlyCompleted ? 1 : 0,
      );
    }

    await _store.putJson(LocalStore.dashboardKey, dash);
  }

  /// Prefer cached subject-detail stats — they reflect local topic edits.
  List<SubjectProgressModel> _enrichProgressRowsFromSubjectDetails(
    List<SubjectProgressModel> rows,
  ) {
    return rows.map((row) {
      final data = _store.getJson(_store.subjectDetailKey(row.subjectId));
      if (data == null) return row;
      try {
        final detail = SubjectDetailModel.fromJson(data);
        return SubjectProgressModel(
          subjectId: row.subjectId,
          subjectName: detail.subjectName,
          iconName: detail.iconName,
          colorCode: detail.colorCode,
          displayOrder: row.displayOrder,
          totalTopics: detail.totalTopics,
          completedTopics: detail.completedTopics,
          completionPercent: detail.completionPercent,
          totalEstimatedHours: row.totalEstimatedHours,
        );
      } catch (_) {
        return row;
      }
    }).toList();
  }

  Future<int?> _resolveExamIdForProgress(Map<String, dynamic> user) async {
    final selected = (user['selectedExamId'] as num?)?.toInt();
    if (selected != null) return selected;

    final activeUserExamId = (user['activeUserExamId'] as num?)?.toInt();
    final exams = await getMyExamsCached();
    for (final exam in exams) {
      if (activeUserExamId != null && exam.id == activeUserExamId) {
        return exam.examId;
      }
      if (exam.isActive) return exam.examId;
    }
    return null;
  }

  Map<String, dynamic> _subjectDetailToProgressMap(
    SubjectDetailModel detail,
    int examId,
  ) {
    var displayOrder = 0;
    final cached = getSubjectProgressCached(examId);
    if (cached != null) {
      for (final row in cached) {
        if (row.subjectId == detail.subjectId) {
          displayOrder = row.displayOrder;
          break;
        }
      }
    }
    return {
      'subjectId': detail.subjectId,
      'subjectName': detail.subjectName,
      'iconName': detail.iconName,
      'colorCode': detail.colorCode,
      'displayOrder': displayOrder,
      'totalTopics': detail.totalTopics,
      'completedTopics': detail.completedTopics,
      'completionPercent': detail.completionPercent,
      'totalEstimatedHours': 0.0,
    };
  }

  void _patchSubjectProgressList(
    Map<String, dynamic> dash,
    Map<String, dynamic> row,
  ) {
    final subjectId = (row['subjectId'] as num).toInt();
    final progress = dash['subjectProgress'];
    if (progress is! List) {
      dash['subjectProgress'] = [row];
      return;
    }

    var updated = false;
    for (var i = 0; i < progress.length; i++) {
      final item = progress[i];
      if (item is Map &&
          (item['subjectId'] as num?)?.toInt() == subjectId) {
        progress[i] = row;
        updated = true;
        break;
      }
    }
    if (!updated) progress.add(row);
  }

  void _patchWeeklyLog(
    Map<String, dynamic> dash,
    String studyDate,
    double hoursDelta,
    int topicsDelta,
  ) {
    final logs = dash['weeklyLogs'];
    final list = logs is List
        ? logs
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList()
        : <Map<String, dynamic>>[];

    var found = false;
    for (final log in list) {
      if (log['studyDate'] == studyDate) {
        log['hoursStudied'] = math.max(
          0.0,
          ((log['hoursStudied'] as num?) ?? 0).toDouble() + hoursDelta,
        );
        log['topicsCompleted'] = math.max(
          0,
          ((log['topicsCompleted'] as num?) ?? 0).toInt() + topicsDelta,
        );
        found = true;
        break;
      }
    }
    if (!found && (hoursDelta != 0 || topicsDelta != 0)) {
      list.add({
        'studyDate': studyDate,
        'hoursStudied': math.max(0.0, hoursDelta),
        'topicsCompleted': math.max(0, topicsDelta),
      });
    }
    dash['weeklyLogs'] = list;
  }

  Future<void> _patchExamSubjectProgressCache(
    int examId,
    Map<String, dynamic> row,
  ) async {
    final list = _store.getJsonList(_store.subjectProgressKey(examId));
    final progress = list != null
        ? list.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];

    final subjectId = (row['subjectId'] as num).toInt();
    var updated = false;
    for (var i = 0; i < progress.length; i++) {
      if ((progress[i]['subjectId'] as num?)?.toInt() == subjectId) {
        progress[i] = row;
        updated = true;
        break;
      }
    }
    if (!updated) progress.add(row);
    await _store.putJson(_store.subjectProgressKey(examId), progress);
  }

  Future<List<UserExamModel>> getMyExamsCached() async {
    final list = _store.getJsonList(LocalStore.myExamsKey);
    if (list == null) return [];
    return list
        .map((e) => UserExamModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  List<SubjectProgressModel>? getSubjectProgressCached(int examId) {
    final list = _store.getJsonList(_store.subjectProgressKey(examId));
    if (list == null) return null;
    return list
        .map((e) => SubjectProgressModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  List<SubjectModel>? getVisibleSubjectsCached(int examId) {
    final list = _store.getJsonList(_store.visibleSubjectsKey(examId));
    if (list == null) return null;
    return list
        .map((e) => SubjectModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// My exams from dedicated key or embedded dashboard cache.
  Future<List<UserExamModel>> resolveMyExamsFromCache() async {
    final fromKey = await getMyExamsCached();
    if (fromKey.isNotEmpty) return fromKey;
    final dashboard = await getDashboardCached();
    if (dashboard != null && dashboard.myExams.isNotEmpty) {
      return dashboard.myExams;
    }
    return const [];
  }

  /// Visible subjects from cache, or derived from subject progress rows.
  List<SubjectModel> resolveVisibleSubjects(int examId) {
    final visible = getVisibleSubjectsCached(examId);
    if (visible != null && visible.isNotEmpty) return visible;

    final progress = getSubjectProgressCached(examId);
    if (progress != null && progress.isNotEmpty) {
      final derived = progress.map((p) => p.toSubjectModel(examId)).toList();
      derived.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
      return derived;
    }
    return const [];
  }

  void cacheEmbeddedDashboardProgress(Map<String, dynamic> data) {
    final progress = data['subjectProgress'];
    if (progress is! List || progress.isEmpty) return;
    final user = data['user'];
    if (user is! Map<String, dynamic>) return;
    final examId = user['selectedExamId'];
    if (examId == null) return;
    _store.putJson(_store.subjectProgressKey((examId as num).toInt()), progress);
  }

  /// Build subject groups purely from local cache (never hits network).
  Future<List<ExamSubjectsCacheGroup>> buildSubjectGroupsFromCache() async {
    final exams = await resolveMyExamsFromCache();
    final dashboard = await getDashboardCached();
    final groups = <ExamSubjectsCacheGroup>[];

    for (final exam in exams) {
      final group = _buildSubjectGroupForExam(exam, dashboard);
      if (group != null) groups.add(group);
    }

    groups.sort((a, b) {
      final ad = a.exam.daysLeft ?? 1 << 20;
      final bd = b.exam.daysLeft ?? 1 << 20;
      return ad.compareTo(bd);
    });
    return groups;
  }

  /// Subjects + progress for one enrolled exam (local cache only).
  Future<ExamSubjectsCacheGroup?> buildSubjectGroupForUserExam(
    int userExamId,
  ) async {
    final exams = await resolveMyExamsFromCache();
    UserExamModel? exam;
    for (final e in exams) {
      if (e.id == userExamId) {
        exam = e;
        break;
      }
    }
    if (exam == null) return null;
    final dashboard = await getDashboardCached();
    return _buildSubjectGroupForExam(exam, dashboard);
  }

  ExamSubjectsCacheGroup? _buildSubjectGroupForExam(
    UserExamModel exam,
    DashboardModel? dashboard,
  ) {
    var progressRows =
        getSubjectProgressCached(exam.examId) ?? const <SubjectProgressModel>[];
    if (progressRows.isEmpty &&
        dashboard != null &&
        exam.isActive &&
        dashboard.subjectProgress.isNotEmpty) {
      progressRows = dashboard.subjectProgress;
    }

    var subjects = resolveVisibleSubjects(exam.examId);
    if (subjects.isEmpty && progressRows.isNotEmpty) {
      subjects = progressRows.map((p) => p.toSubjectModel(exam.examId)).toList();
    }
    if (subjects.isEmpty && progressRows.isEmpty) return null;

    progressRows = _enrichProgressRowsFromSubjectDetails(progressRows);

    return ExamSubjectsCacheGroup(
      exam: exam,
      subjects: subjects,
      progressRows: progressRows,
    );
  }

  /// Local-first read — never hits network during normal usage.
  Future<DashboardModel> getDashboard({bool forceRemote = false}) async {
    final cached = await getDashboardCached();
    if (!forceRemote) {
      if (cached != null) return cached;
      throw StateError('Dashboard not available offline. Tap SYNC while online.');
    }
    return fetchDashboardFromNetwork(fallback: cached);
  }

  Future<DashboardModel> fetchDashboardFromNetwork({DashboardModel? fallback}) async {
    try {
      ApiCallTracker.instance.record('GET ${ApiEndpoints.dashboard}');
      final response = await _client.dio.get(ApiEndpoints.dashboard);
      final data = response.data['data'] as Map<String, dynamic>;
      await storeSyncedDashboard(
        data,
        profileUser: _store.getJson(LocalStore.userProfileKey),
      );
      return DashboardModel.fromJson(_store.getJson(LocalStore.dashboardKey)!);
    } catch (_) {
      if (fallback != null) return fallback;
      rethrow;
    }
  }

  Future<List<UserExamModel>> getMyExams({bool forceRemote = false}) async {
    final cached = await resolveMyExamsFromCache();
    if (!forceRemote) return cached;
    try {
      ApiCallTracker.instance.record('GET ${ApiEndpoints.myExams}');
      final response = await _client.dio.get(ApiEndpoints.myExams);
      final list = response.data['data'] as List<dynamic>;
      await _store.putJson(LocalStore.myExamsKey, list);
      return list.map((e) => UserExamModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return cached;
    }
  }

  Future<List<SubjectProgressModel>> getSubjectProgressByExam(
    int examId, {
    bool forceRemote = false,
  }) async {
    final cached = getSubjectProgressCached(examId) ?? const <SubjectProgressModel>[];
    if (!forceRemote) return cached;
    try {
      ApiCallTracker.instance.record('GET ${ApiEndpoints.subjectProgress(examId)}');
      final response = await _client.dio.get(ApiEndpoints.subjectProgress(examId));
      final list = response.data['data'] as List<dynamic>;
      await _store.putJson(_store.subjectProgressKey(examId), list);
      return list
          .map((e) => SubjectProgressModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return cached;
    }
  }

  Future<List<SubjectModel>> getVisibleSubjectsByExam(
    int examId, {
    bool forceRemote = false,
  }) async {
    final cached = resolveVisibleSubjects(examId);
    if (!forceRemote) return cached;
    try {
      final groups = await getExamSubjectGroups(examId);
      final subjects = groups
          .expand(
            (group) => group.isOptional
                ? group.subjects.where((subject) => subject.selected)
                : group.subjects,
          )
          .toList();
      await _store.putJson(
        _store.visibleSubjectsKey(examId),
        subjects.map((s) => s.toJson()).toList(),
      );
      return subjects;
    } catch (_) {
      return cached;
    }
  }

  // ── Mutations (always remote; queue handled by callers when offline) ─────

  Future<UserModel> addMyExam({
    required int examId,
    DateTime? examDate,
    List<Map<String, dynamic>> subjectSelections = const [],
  }) async {
    ApiCallTracker.instance.record('POST ${ApiEndpoints.myExams}');
    final response = await _client.dio.post(
      ApiEndpoints.myExams,
      data: {
        'examId': examId,
        if (examDate != null) 'examDate': _fmtLocalDate(examDate),
        if (subjectSelections.isNotEmpty) 'subjectSelections': subjectSelections,
      },
    );
    return UserModel.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  Future<List<ExamSubjectGroupModel>> getExamSubjectGroups(int examId) async {
    ApiCallTracker.instance.record('GET ${ApiEndpoints.examSubjectGroups(examId)}');
    final response = await _client.dio.get(ApiEndpoints.examSubjectGroups(examId));
    final list = response.data['data'] as List<dynamic>;
    return list
        .map((item) => ExamSubjectGroupModel.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<UserModel> updateSubjectSelections(
    int userExamId,
    List<Map<String, dynamic>> subjectSelections,
  ) async {
    final response = await _client.dio.put(
      ApiEndpoints.subjectSelections(userExamId),
      data: subjectSelections,
    );
    return UserModel.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  Future<UserModel> updateMyExamDate(int userExamId, DateTime examDate) async {
    final response = await _client.dio.patch(
      ApiEndpoints.myExamDate(userExamId),
      data: {'examDate': _fmtLocalDate(examDate)},
    );
    return UserModel.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  /// Local-first: patch cache immediately; sync PATCH when online / on SYNC.
  Future<UserModel> setActiveMyExam(int userExamId) async {
    final user = await _patchActiveExamLocally(userExamId);

    if (await isDeviceOnline()) {
      try {
        return await _setActiveMyExamRemote(userExamId);
      } catch (_) {
        await _queueActiveExamChange(userExamId);
        return user;
      }
    }

    await _queueActiveExamChange(userExamId);
    return user;
  }

  Future<UserModel> _setActiveMyExamRemote(int userExamId) async {
    ApiCallTracker.instance.record('PATCH active exam');
    final response =
        await _client.dio.patch(ApiEndpoints.setActiveMyExam(userExamId));
    final remote =
        UserModel.fromJson(response.data['data'] as Map<String, dynamic>);
    await _applyUserToCache(remote);
    await _removeQueuedActiveExamChanges();
    return remote;
  }

  Future<void> flushQueuedActiveExam(Map<String, dynamic> item) async {
    final userExamId = item['payload']?['userExamId'];
    if (userExamId == null) {
      await _removeQueuedActiveExamChanges();
      return;
    }
    try {
      await _setActiveMyExamRemote((userExamId as num).toInt());
    } catch (_) {
      final profile = _store.getJson(LocalStore.userProfileKey);
      final activeId = (profile?['activeUserExamId'] as num?)?.toInt();
      if (activeId == (userExamId as num).toInt()) {
        await _removeQueuedActiveExamChanges();
        return;
      }
      rethrow;
    }
  }

  Future<UserModel> _patchActiveExamLocally(int userExamId) async {
    final exams = await resolveMyExamsFromCache();
    UserExamModel? target;
    final updatedExams = exams.map((exam) {
      final active = exam.id == userExamId;
      if (active) target = exam;
      return UserExamModel(
        id: exam.id,
        examId: exam.examId,
        examName: exam.examName,
        examDate: exam.examDate,
        daysLeft: exam.daysLeft,
        totalSubjects: exam.totalSubjects,
        progressPercent: exam.progressPercent,
        dailyTargetHours: exam.dailyTargetHours,
        weeklyTargetHours: exam.weeklyTargetHours,
        isActive: active,
      );
    }).toList();

    if (target == null) {
      throw StateError('Exam not found offline. Tap SYNC while online.');
    }
    final activeExam = target!;

    await _store.putJson(
      LocalStore.myExamsKey,
      updatedExams.map((e) => e.toJson()).toList(),
    );

    final profile = Map<String, dynamic>.from(
      _store.getJson(LocalStore.userProfileKey) ??
          (await getDashboardCached())?.user.toJson() ??
          {},
    );
    profile['selectedExamId'] = activeExam.examId;
    profile['selectedExamName'] = activeExam.examName;
    profile['activeUserExamId'] = userExamId;
    profile['examDate'] = activeExam.examDate;
    profile['userExams'] = updatedExams.map((e) => e.toJson()).toList();

    final dashData = _store.getJson(LocalStore.dashboardKey);
    if (dashData != null) {
      final dash = Map<String, dynamic>.from(dashData);
      dash['user'] = Map<String, dynamic>.from(profile);
      dash['myExams'] = updatedExams.map((e) => e.toJson()).toList();
      await _store.putJson(LocalStore.dashboardKey, dash);
    }

    await _store.putJson(LocalStore.userProfileKey, profile);
    return UserModel.fromJson(profile);
  }

  Future<void> _applyUserToCache(UserModel user) async {
    await _store.putJson(LocalStore.userProfileKey, user.toJson());
    final dashData = _store.getJson(LocalStore.dashboardKey);
    if (dashData != null) {
      final dash = Map<String, dynamic>.from(dashData);
      dash['user'] = user.toJson();
      if (user.userExams.isNotEmpty) {
        dash['myExams'] = user.userExams.map((e) => e.toJson()).toList();
        await _store.putJson(
          LocalStore.myExamsKey,
          user.userExams.map((e) => e.toJson()).toList(),
        );
      }
      await _store.putJson(LocalStore.dashboardKey, dash);
    }
  }

  Future<void> _queueActiveExamChange(int userExamId) async {
    await _removeQueuedActiveExamChanges();
    await _offlineQueue.enqueue(
      entityType: 'USER_EXAM',
      entityId: userExamId.toString(),
      action: 'SET_ACTIVE_EXAM',
      payload: {'userExamId': userExamId},
    );
  }

  Future<void> _removeQueuedActiveExamChanges() async {
    final queue = _offlineQueue.pendingItems
        .where((e) => e['action'] != 'SET_ACTIVE_EXAM')
        .toList();
    await _store.putJson(LocalStore.offlineQueueKey, queue);
  }

  Future<UserModel> deleteMyExam(int userExamId) async {
    final response = await _client.dio.delete(ApiEndpoints.deleteMyExam(userExamId));
    return UserModel.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  Future<List<ExamModel>> getExams() async {
    ApiCallTracker.instance.record('GET ${ApiEndpoints.exams}');
    final response = await _client.dio.get(ApiEndpoints.exams);
    final list = response.data['data'] as List<dynamic>;
    return list.map((e) => ExamModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> selectExam(int examId) async {
    await _client.dio.patch(ApiEndpoints.selectExam(examId));
  }

  Future<UserModel> setExamGoal({
    required DateTime examDate,
    DateTime? syllabusTargetDate,
    int? userExamId,
  }) async {
    final body = {
      if (userExamId != null) 'userExamId': userExamId,
      'examDate': _fmtLocalDate(examDate),
      if (syllabusTargetDate != null)
        'syllabusTargetDate': _fmtLocalDate(syllabusTargetDate),
    };
    final response = await _client.dio.post(ApiEndpoints.examGoal, data: body);
    return UserModel.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  Future<void> updateStudyHours(double dailyTargetHours) async {
    ApiCallTracker.instance.record('PATCH ${ApiEndpoints.studyHours}');
    await _client.dio.patch(
      ApiEndpoints.studyHours,
      data: {'dailyTargetHours': dailyTargetHours},
    );
  }

  Future<void> updateStudyHoursLocal(double dailyTargetHours) async {
    final data = _store.getJson(LocalStore.dashboardKey);
    if (data == null) return;
    final user = data['user'];
    if (user is Map<String, dynamic>) {
      user['dailyTargetHours'] = dailyTargetHours;
      user['weeklyTargetHours'] = (dailyTargetHours * 7 * 10).round() / 10.0;
      await _store.putJson(LocalStore.dashboardKey, data);
      await _store.putJson(LocalStore.userProfileKey, user);
    }
  }

  Future<List<SubjectModel>> getSubjectsByExam(int examId) async {
    final response = await _client.dio.get(ApiEndpoints.subjectsByExam(examId));
    final list = response.data['data'] as List<dynamic>;
    return list.map((e) => SubjectModel.fromJson(e as Map<String, dynamic>)).toList();
  }
}
