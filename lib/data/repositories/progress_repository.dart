import '../models/subject_detail_model.dart';
import '../models/topic_model.dart';
import '../../core/local/api_call_tracker.dart';
import '../../core/local/local_store.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/sync/offline_queue_service.dart';
import '../../core/sync/sync_service.dart';

class ProgressRepository {
  final ApiClient _client;
  final LocalStore _store;
  final OfflineQueueService _offlineQueue;
  final SyncService _syncService;

  ProgressRepository({
    required ApiClient client,
    required LocalStore store,
    required OfflineQueueService offlineQueue,
    required SyncService syncService,
  })  : _client = client,
        _store = store,
        _offlineQueue = offlineQueue,
        _syncService = syncService;

  Future<SubjectDetailModel?> getSubjectDetailCached(int subjectId) async {
    final data = _store.getJson(_store.subjectDetailKey(subjectId));
    if (data == null) return null;
    return SubjectDetailModel.fromJson(data);
  }

  Future<SubjectDetailModel> getSubjectDetail(
    int subjectId, {
    bool forceRemote = false,
  }) async {
    if (!forceRemote) {
      final cached = await getSubjectDetailCached(subjectId);
      if (cached != null) return cached;
    }
    ApiCallTracker.instance.record('GET ${ApiEndpoints.subjectDetail(subjectId)}');
    final response = await _client.dio.get(ApiEndpoints.subjectDetail(subjectId));
    final data = response.data['data'] as Map<String, dynamic>;
    await _store.putJson(_store.subjectDetailKey(subjectId), data);
    return SubjectDetailModel.fromJson(data);
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
    if (!await _syncService.isOnline()) {
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
    if (!await _syncService.isOnline()) {
      await _offlineQueue.enqueue(type: 'LOG_STUDY', payload: payload);
      return;
    }
    ApiCallTracker.instance.record('POST ${ApiEndpoints.logStudy}');
    await _client.dio.post(ApiEndpoints.logStudy, data: payload);
  }

  Future<List<TopicModel>> getTopicsByChapter(int chapterId) async {
    final response = await _client.dio.get(ApiEndpoints.topicsByChapter(chapterId));
    final list = response.data['data'] as List<dynamic>;
    return list.map((e) => TopicModel.fromJson(e as Map<String, dynamic>)).toList();
  }
}
