import 'dart:async';

import '../models/subject_detail_model.dart';
import '../models/topic_model.dart';
import '../../core/local/api_call_tracker.dart';
import '../../core/local/local_store.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/sync/offline_queue_service.dart';

/// All reads from local cache. All writes to cache + pending sync queue.
class ProgressRepository {
  ProgressRepository({
    required ApiClient client,
    required LocalStore store,
    required OfflineQueueService offlineQueue,
  })  : _client = client,
        _store = store,
        _offlineQueue = offlineQueue;

  final ApiClient _client;
  final LocalStore _store;
  final OfflineQueueService _offlineQueue;

  Future<SubjectDetailModel?> getSubjectDetailCached(int subjectId) async {
    final data = _store.getJson(_store.subjectDetailKey(subjectId));
    if (data == null) return null;
    return SubjectDetailModel.fromJson(data);
  }

  /// Local-first read — never hits network during normal usage.
  Future<SubjectDetailModel> getSubjectDetail(
    int subjectId, {
    bool forceRemote = false,
  }) async {
    final cached = await getSubjectDetailCached(subjectId);
    if (!forceRemote) {
      if (cached != null) return cached;
      throw StateError(
        'Subject $subjectId not available offline. Tap SYNC while online.',
      );
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

  /// Queue-only write — synced when user taps SYNC.
  Future<void> markTopicComplete({
    required int topicId,
    required bool isCompleted,
    double actualHours = 0.0,
  }) async {
    await _offlineQueue.enqueue(
      entityType: 'TOPIC',
      entityId: topicId.toString(),
      action: isCompleted ? 'COMPLETE_TOPIC' : 'ADD_STUDY_HOURS',
      payload: {
        'topicId': topicId,
        'isCompleted': isCompleted,
        'actualHours': actualHours,
      },
    );
  }

  Future<void> logStudyHours({
    required String studyDate,
    required double hoursStudied,
    int topicsCompleted = 0,
  }) async {
    await _offlineQueue.enqueue(
      entityType: 'STUDY_LOG',
      entityId: studyDate,
      action: 'LOG_STUDY_HOURS',
      payload: {
        'studyDate': studyDate,
        'hoursStudied': hoursStudied,
        'topicsCompleted': topicsCompleted,
      },
    );
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

  /// Fire-and-forget: patch local cache then queue for SYNC.
  void persistTopicProgressInBackground({
    required int subjectId,
    required int topicId,
    required bool isCompleted,
    required double actualHours,
    double? studyHoursDelta,
    String? studyDate,
  }) {
    unawaited(_persistLocally(
      subjectId: subjectId,
      topicId: topicId,
      isCompleted: isCompleted,
      actualHours: actualHours,
      studyHoursDelta: studyHoursDelta,
      studyDate: studyDate,
    ));
  }

  Future<void> _persistLocally({
    required int subjectId,
    required int topicId,
    required bool isCompleted,
    required double actualHours,
    double? studyHoursDelta,
    String? studyDate,
  }) async {
    await patchTopicInCache(
      subjectId: subjectId,
      topicId: topicId,
      actualHours: actualHours,
      isCompleted: isCompleted,
      status: isCompleted ? 'COMPLETED' : (actualHours > 0 ? 'IN_PROGRESS' : null),
    );
    await markTopicComplete(
      topicId: topicId,
      isCompleted: isCompleted,
      actualHours: actualHours,
    );
    if (studyHoursDelta != null && studyHoursDelta > 0 && studyDate != null) {
      await logStudyHours(
        studyDate: studyDate,
        hoursStudied: studyHoursDelta,
      );
    }
  }

  Future<List<TopicModel>> getTopicsByChapter(int chapterId) async {
    throw UnimplementedError('Use cached subject detail offline.');
  }
}
