import 'dart:async';

import '../models/subject_detail_model.dart';
import '../models/topic_model.dart';
import '../../core/local/api_call_tracker.dart';
import '../../core/local/local_store.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/connectivity_helper.dart';
import '../../core/sync/offline_queue_service.dart';

class ProgressRepository {
  final ApiClient _client;
  final LocalStore _store;
  final OfflineQueueService _offlineQueue;

  ProgressRepository({
    required ApiClient client,
    required LocalStore store,
    required OfflineQueueService offlineQueue,
  })  : _client = client,
        _store = store,
        _offlineQueue = offlineQueue;

  Future<bool> _isOnline() => isDeviceOnline();

  Future<SubjectDetailModel?> getSubjectDetailCached(int subjectId) async {
    final data = _store.getJson(_store.subjectDetailKey(subjectId));
    if (data == null) return null;
    return SubjectDetailModel.fromJson(data);
  }

  Future<SubjectDetailModel> getSubjectDetail(
    int subjectId, {
    bool forceRemote = false,
  }) async {
    final cached = await getSubjectDetailCached(subjectId);
    if (!forceRemote) {
      if (cached != null) return cached;
      throw StateError('Subject $subjectId not available offline. Sync when online.');
    }
    try {
      ApiCallTracker.instance.record('GET ${ApiEndpoints.subjectDetail(subjectId)}');
      final response = await _client.dio.get(ApiEndpoints.subjectDetail(subjectId));
      final data = response.data['data'] as Map<String, dynamic>;
      await _store.putJson(_store.subjectDetailKey(subjectId), data);
      return SubjectDetailModel.fromJson(data);
    } catch (_) {
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<void> markTopicComplete({
    required int topicId,
    required bool isCompleted,
    double actualHours = 0.0,
  }) async {
    final payload = {
      'topicId': topicId,
      'isCompleted': isCompleted,
      'actualHours': actualHours,
    };
    if (!await _isOnline()) {
      await _offlineQueue.enqueue(type: 'TOPIC_PROGRESS', payload: payload);
      return;
    }
    try {
      ApiCallTracker.instance.record('POST ${ApiEndpoints.updateProgress}');
      await _client.dio.post(ApiEndpoints.updateProgress, data: payload);
    } catch (_) {
      await _offlineQueue.enqueue(type: 'TOPIC_PROGRESS', payload: payload);
      rethrow;
    }
  }

  Future<void> logStudyHours({
    required String studyDate,
    required double hoursStudied,
    int topicsCompleted = 0,
  }) async {
    final payload = {
      'studyDate': studyDate,
      'hoursStudied': hoursStudied,
      'topicsCompleted': topicsCompleted,
    };
    if (!await _isOnline()) {
      await _offlineQueue.enqueue(type: 'LOG_STUDY', payload: payload);
      return;
    }
    ApiCallTracker.instance.record('POST ${ApiEndpoints.logStudy}');
    await _client.dio.post(ApiEndpoints.logStudy, data: payload);
  }

  /// Updates cached subject detail immediately (no network).
  Future<SubjectDetailModel?> patchTopicInCache({
    required int subjectId,
    required int topicId,
    double? actualHours,
    bool? isCompleted,
    String? status,
  }) async {
    final data = _store.getJson(_store.subjectDetailKey(subjectId));
    if (data == null) return null;

    final chapters = data['chapters'];
    if (chapters is! List) return null;

    for (final chapter in chapters) {
      if (chapter is! Map<String, dynamic>) continue;
      final topics = chapter['topics'];
      if (topics is! List) continue;
      for (final topic in topics) {
        if (topic is! Map<String, dynamic>) continue;
        if (topic['id'] != topicId) continue;

        if (actualHours != null) topic['actualHours'] = actualHours;
        if (isCompleted != null) topic['isCompleted'] = isCompleted;
        if (status != null) {
          topic['status'] = status;
        } else if (isCompleted == true) {
          topic['status'] = 'COMPLETED';
        } else if (actualHours != null && actualHours > 0) {
          topic['status'] = 'IN_PROGRESS';
        }
      }
    }

    _recalculateSubjectStats(data);
    await _store.putJson(_store.subjectDetailKey(subjectId), data);
    return SubjectDetailModel.fromJson(data);
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

  /// Fire-and-forget API sync after local cache is already updated.
  void persistTopicProgressInBackground({
    required int topicId,
    required bool isCompleted,
    required double actualHours,
    double? studyHoursDelta,
    String? studyDate,
  }) {
    unawaited(_persistTopicProgress(
      topicId: topicId,
      isCompleted: isCompleted,
      actualHours: actualHours,
      studyHoursDelta: studyHoursDelta,
      studyDate: studyDate,
    ));
  }

  Future<void> _persistTopicProgress({
    required int topicId,
    required bool isCompleted,
    required double actualHours,
    double? studyHoursDelta,
    String? studyDate,
  }) async {
    try {
      await markTopicComplete(
        topicId: topicId,
        isCompleted: isCompleted,
        actualHours: actualHours,
      );
      if (studyHoursDelta != null &&
          studyHoursDelta > 0 &&
          studyDate != null) {
        await logStudyHours(
          studyDate: studyDate,
          hoursStudied: studyHoursDelta,
        );
      }
    } catch (_) {
      // Local cache is already updated; offline queue handles failures.
    }
  }

  Future<List<TopicModel>> getTopicsByChapter(int chapterId) async {
    final response = await _client.dio.get(ApiEndpoints.topicsByChapter(chapterId));
    final list = response.data['data'] as List<dynamic>;
    return list.map((e) => TopicModel.fromJson(e as Map<String, dynamic>)).toList();
  }
}
