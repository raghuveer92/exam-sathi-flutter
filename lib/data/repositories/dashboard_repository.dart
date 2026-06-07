import '../models/dashboard_model.dart';
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
    return DashboardModel.fromJson(data);
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
      await _store.putJson(LocalStore.dashboardKey, data);
      cacheEmbeddedDashboardProgress(data);
      final user = data['user'];
      if (user != null) {
        await _store.putJson(LocalStore.userProfileKey, user);
      }
      return DashboardModel.fromJson(data);
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
    }
    await _store.putJson(LocalStore.dashboardKey, data);
    await _store.putJson(LocalStore.userProfileKey, user);
  }

  Future<List<SubjectModel>> getSubjectsByExam(int examId) async {
    final response = await _client.dio.get(ApiEndpoints.subjectsByExam(examId));
    final list = response.data['data'] as List<dynamic>;
    return list.map((e) => SubjectModel.fromJson(e as Map<String, dynamic>)).toList();
  }
}
