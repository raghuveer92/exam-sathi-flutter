import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../core/local/api_call_tracker.dart';
import '../../core/local/local_store.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/sync/offline_queue_service.dart';
import '../models/mock_test_model.dart';

class MockTestRepository {
  MockTestRepository({
    required ApiClient client,
    required LocalStore store,
    required OfflineQueueService offlineQueue,
  })  : _client = client,
        _store = store,
        _offlineQueue = offlineQueue;

  final ApiClient _client;
  final LocalStore _store;
  final OfflineQueueService _offlineQueue;
  final _uuid = const Uuid();

  Future<MockTestInfoModel?> getTopicInfoCached(int topicId) async {
    final raw = _store.getString(_store.topicMockInfoKey(topicId));
    if (raw == null) return null;
    return MockTestInfoModel.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  Future<MockTestInfoModel> getTopicInfo(int topicId, {bool forceRemote = false}) async {
    if (!forceRemote) {
      final cached = await getTopicInfoCached(topicId);
      if (cached != null) return cached;
    }
    return _fetchTopicInfoRemote(topicId);
  }

  Future<MockTestInfoModel> _fetchTopicInfoRemote(int topicId) async {
    ApiCallTracker.instance.record('GET ${ApiEndpoints.mockTestTopicInfo(topicId)}');
    final response = await _client.dio.get(ApiEndpoints.mockTestTopicInfo(topicId));
    final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
    await _store.putString(_store.topicMockInfoKey(topicId), jsonEncode(data));
    return MockTestInfoModel.fromJson(data);
  }

  /// Called during SYNC — caches question bank for offline tests.
  Future<int> syncTopicForOffline(int topicId) async {
    final info = await _fetchTopicInfoRemote(topicId);
    if (!info.canStart) {
      await _store.deleteKey(_store.topicMockInfoKey(topicId));
      await _store.deleteKey(_store.mockTestQuestionsKey(topicId));
      return 0;
    }
    final attempt = await _startTestRemote(topicId);
    await _store.putString(
      _store.mockTestQuestionsKey(topicId),
      jsonEncode(_attemptToCacheJson(attempt)),
    );
    return attempt.totalQuestions;
  }

  Future<void> clearOfflineCache() => _store.clearMockTestCache();

  Map<String, dynamic> _attemptToCacheJson(MockTestAttemptModel attempt) {
    return {
      'id': attempt.id,
      'topicId': attempt.topicId,
      'topicTitle': attempt.topicTitle,
      'status': attempt.status,
      'durationMinutes': attempt.durationMinutes,
      'totalQuestions': attempt.totalQuestions,
      'questions': attempt.questions
          .map((q) => {
                'questionId': q.questionId,
                'questionText': q.questionText,
                'questionType': q.questionType,
                'marks': q.marks,
                'negativeMarks': q.negativeMarks,
                'options': q.options
                    .map((o) => {
                          'id': o.id,
                          'optionKey': o.optionKey,
                          'optionText': o.optionText,
                        })
                    .toList(),
              })
          .toList(),
    };
  }

  MockTestAttemptModel? _getCachedQuestionBank(int topicId) {
    final raw = _store.getString(_store.mockTestQuestionsKey(topicId));
    if (raw == null) return null;
    return MockTestAttemptModel.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  /// Local-first start — uses cached questions; no network.
  Future<MockTestAttemptModel> startTest(int topicId) async {
    final bank = _getCachedQuestionBank(topicId);
    if (bank == null) {
      throw StateError(
        'Test not available offline. Tap SYNC while online to download.',
      );
    }
    final localId = -DateTime.now().millisecondsSinceEpoch;
    return MockTestAttemptModel(
      id: localId,
      topicId: bank.topicId,
      topicTitle: bank.topicTitle,
      status: 'IN_PROGRESS',
      durationMinutes: bank.durationMinutes,
      totalQuestions: bank.totalQuestions,
      questions: bank.questions,
    );
  }

  Future<MockTestAttemptModel> _startTestRemote(int topicId) async {
    ApiCallTracker.instance.record('POST ${ApiEndpoints.mockTestStart(topicId)}');
    final response = await _client.dio.post(ApiEndpoints.mockTestStart(topicId));
    final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
    return MockTestAttemptModel.fromJson(data);
  }

  /// Local-first submit — stores result + queues for SYNC upload.
  Future<MockTestAttemptModel> submitTest(
    int attemptId, {
    required int topicId,
    required int timeSpentSeconds,
    required List<Map<String, dynamic>> answers,
    bool timedOut = false,
  }) async {
    final clientId = _uuid.v4();

    final payload = {
      'topicId': topicId,
      'attemptId': attemptId,
      'timeSpentSeconds': timeSpentSeconds,
      'timedOut': timedOut,
      'answers': answers,
    };

    await _offlineQueue.enqueue(
      entityType: 'MOCK_TEST',
      entityId: attemptId.toString(),
      action: 'SUBMIT_TEST',
      payload: payload,
    );

    final localResult = MockTestAttemptModel(
      id: attemptId,
      topicId: topicId,
      topicTitle: 'Offline attempt',
      status: timedOut ? 'TIMED_OUT' : 'SUBMITTED',
      durationMinutes: (timeSpentSeconds / 60).ceil(),
      timeSpentSeconds: timeSpentSeconds,
      totalQuestions: answers.length,
      questions: const [],
    );

    await _store.putJson(
      _store.mockTestLocalResultKey(clientId),
      {
        'attemptId': attemptId,
        'topicId': topicId,
        'timeSpentSeconds': timeSpentSeconds,
        'timedOut': timedOut,
        'answers': answers,
        'status': localResult.status,
      },
    );

    return localResult;
  }

  Future<void> flushQueuedSubmit(Map<String, dynamic> item) async {
    final payload = item['payload'] as Map<String, dynamic>;
    final topicId = (payload['topicId'] as num).toInt();
    final attempt = await _startTestRemote(topicId);
    await _submitTestRemote(
      attempt.id,
      timeSpentSeconds: (payload['timeSpentSeconds'] as num?)?.toInt() ?? 0,
      answers: (payload['answers'] as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      timedOut: payload['timedOut'] as bool? ?? false,
    );
  }

  Future<MockTestAttemptModel> _submitTestRemote(
    int attemptId, {
    required int timeSpentSeconds,
    required List<Map<String, dynamic>> answers,
    bool timedOut = false,
  }) async {
    ApiCallTracker.instance.record('POST ${ApiEndpoints.mockTestSubmit(attemptId)}');
    final response = await _client.dio.post(
      ApiEndpoints.mockTestSubmit(attemptId),
      data: {
        'timeSpentSeconds': timeSpentSeconds,
        'timedOut': timedOut,
        'answers': answers,
      },
    );
    final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
    return MockTestAttemptModel.fromJson(data);
  }

  Future<MockTestAttemptModel> getAttempt(int attemptId, {bool review = false}) async {
    final response = await _client.dio.get(
      ApiEndpoints.mockTestAttempt(attemptId),
      queryParameters: review ? {'review': true} : null,
    );
    final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
    return MockTestAttemptModel.fromJson(data);
  }

  Future<List<MockTestAttemptModel>> getAttempts(int topicId) async {
    final response = await _client.dio.get(ApiEndpoints.mockTestAttempts(topicId));
    final list = (response.data as Map<String, dynamic>)['data'] as List<dynamic>;
    return list.map((e) => MockTestAttemptModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<MockTestPerformanceModel?> getPerformanceCached() async {
    final data = _store.getJson(LocalStore.mockPerformanceKey);
    if (data == null) return null;
    return MockTestPerformanceModel.fromJson(data);
  }

  Future<MockTestPerformanceModel> getPerformance({bool forceRemote = false}) async {
    if (!forceRemote) {
      final cached = await getPerformanceCached();
      if (cached != null) return cached;
      throw StateError('Performance not cached. Sync when online.');
    }
    ApiCallTracker.instance.record('GET ${ApiEndpoints.mockTestPerformance}');
    final response = await _client.dio.get(ApiEndpoints.mockTestPerformance);
    final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
    await _store.putJson(LocalStore.mockPerformanceKey, data);
    return MockTestPerformanceModel.fromJson(data);
  }
}
