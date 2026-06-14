import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'package:logger/logger.dart';

import '../../core/local/api_call_tracker.dart';
import '../../core/local/local_store.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/api_error_message.dart';
import '../../core/sync/offline_queue_service.dart';
import '../models/mock_test_model.dart';

class MockTestRepository {
  MockTestRepository({
    required ApiClient client,
    required LocalStore store,
    required OfflineQueueService offlineQueue,
    Logger? logger,
  })  : _client = client,
        _store = store,
        _offlineQueue = offlineQueue,
        _logger = logger ?? Logger();

  final ApiClient _client;
  final LocalStore _store;
  final OfflineQueueService _offlineQueue;
  final Logger _logger;
  final _uuid = const Uuid();

  Future<MockTestInfoModel?> getTopicInfoCached(int topicId) async {
    final raw = _store.getString(_store.topicMockInfoKey(topicId));
    if (raw == null) return null;
    return MockTestInfoModel.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  Future<MockTestInfoModel> getTopicInfo(int topicId,
      {bool forceRemote = false}) async {
    if (!forceRemote) {
      final cached = await getTopicInfoCached(topicId);
      if (cached != null) return cached;
    }
    return _fetchTopicInfoRemote(topicId);
  }

  Future<MockTestInfoModel> _fetchTopicInfoRemote(int topicId) async {
    ApiCallTracker.instance
        .record('GET ${ApiEndpoints.mockTestTopicInfo(topicId)}');
    final response =
        await _client.dio.get(ApiEndpoints.mockTestTopicInfo(topicId));
    final data =
        (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
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

  Future<void> _cacheLatestTopicResult(MockTestAttemptModel result) async {
    await _store.putJson(
      _store.latestTopicMockResultKey(result.topicId),
      _attemptResultToJson(result),
    );
  }

  MockTestAttemptModel? getLatestTopicResultCached(int topicId) {
    final data = _store.getJson(_store.latestTopicMockResultKey(topicId));
    if (data == null) return null;
    return MockTestAttemptModel.fromJson(data);
  }

  Map<int, MockTestAttemptModel> getLatestTopicResultsCached(
    Iterable<int> topicIds,
  ) {
    final results = <int, MockTestAttemptModel>{};
    for (final topicId in topicIds) {
      final result = getLatestTopicResultCached(topicId);
      if (result != null && result.isCompleted) {
        results[topicId] = result;
      }
    }
    return results;
  }

  Future<MockTestAttemptModel?> getLatestTopicResult(
    int topicId, {
    bool forceRemote = false,
  }) async {
    if (!forceRemote) {
      final cached = getLatestTopicResultCached(topicId);
      if (cached != null) return cached;
    }
    final attempts = await getAttempts(topicId);
    for (final attempt in attempts) {
      if (attempt.isCompleted) {
        await _cacheLatestTopicResult(attempt);
        return attempt;
      }
    }
    return null;
  }

  Map<String, dynamic> _attemptResultToJson(MockTestAttemptModel attempt) {
    return {
      'id': attempt.id,
      'topicId': attempt.topicId,
      'topicTitle': attempt.topicTitle,
      'status': attempt.status,
      'durationMinutes': attempt.durationMinutes,
      'timeSpentSeconds': attempt.timeSpentSeconds,
      'totalQuestions': attempt.totalQuestions,
      'correctCount': attempt.correctCount,
      'incorrectCount': attempt.incorrectCount,
      'skippedCount': attempt.skippedCount,
      'score': attempt.score,
      'maxScore': attempt.maxScore,
      'percentage': attempt.percentage,
      'review': attempt.review
          .map((r) => {
                'questionId': r.questionId,
                'sheetQuestionId': r.sheetQuestionId,
                'questionText': r.questionText,
                'selectedOptionKeys': r.selectedOptionKeys,
                'correctOptionKeys': r.correctOptionKeys,
                'explanation': r.explanation,
                'isCorrect': r.isCorrect,
                'marksAwarded': r.marksAwarded,
              })
          .toList(),
    };
  }

  /// Start test — tries Google Sheets API first, then offline cache on connectivity loss only.
  Future<MockTestAttemptModel> startTest(int topicId) async {
    _logger.i('[MockTest] startTest topicId=$topicId — sheet API first');
    try {
      final attempt = await _startSheetTopicTestRemote(topicId);
      _logger.i(
        '[MockTest] sheet start ok topicId=$topicId attemptId=${attempt.id} '
        'questions=${attempt.totalQuestions} sheetBacked=${attempt.questions.any((q) => q.sheetQuestionId != null)}',
      );
      return attempt;
    } catch (e, st) {
      _logger.w(
        '[MockTest] sheet start failed topicId=$topicId — ${apiErrorMessage(e)}',
        error: e,
        stackTrace: st,
      );
      if (!_shouldFallbackToOfflineCache(e)) {
        rethrow;
      }
    }

    _logger.i('[MockTest] falling back to offline cache topicId=$topicId');
    final bank = _getCachedQuestionBank(topicId);
    if (bank == null) {
      _logger.e(
        '[MockTest] no offline question bank topicId=$topicId — sync required',
      );
      throw StateError(
        'Test not available offline. Tap SYNC while online to download.',
      );
    }
    _logger.i(
      '[MockTest] offline start topicId=$topicId questions=${bank.totalQuestions}',
    );
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

  Future<MockTestAttemptModel> _startSheetTopicTestRemote(int topicId) async {
    final endpoint = ApiEndpoints.sheetTopicStart(topicId);
    ApiCallTracker.instance.record('GET $endpoint');
    _logger.d('[MockTest] GET $endpoint');
    final response = await _client.dio.get(endpoint);
    final data =
        (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
    return MockTestAttemptModel.fromJson(data);
  }

  bool _shouldFallbackToOfflineCache(Object error) {
    if (error is! DioException) return false;
    return error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout;
  }

  Future<MockTestAttemptModel> _startTestRemote(int topicId) async {
    ApiCallTracker.instance
        .record('POST ${ApiEndpoints.mockTestStart(topicId)}');
    final response =
        await _client.dio.post(ApiEndpoints.mockTestStart(topicId));
    final data =
        (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
    return MockTestAttemptModel.fromJson(data);
  }

  /// Local-first submit — stores result + queues for SYNC upload.
  Future<MockTestAttemptModel> submitTest(
    int attemptId, {
    required int topicId,
    required int timeSpentSeconds,
    required List<Map<String, dynamic>> answers,
    bool timedOut = false,
    bool sheetBacked = false,
  }) async {
    if (sheetBacked && attemptId > 0) {
      final result = await _submitSheetTopicTestRemote(
        attemptId: attemptId,
        timeSpentSeconds: timeSpentSeconds,
        answers: answers,
        timedOut: timedOut,
      );
      await _cacheLatestTopicResult(result);
      return result;
    }

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
    await _cacheLatestTopicResult(localResult);

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
    ApiCallTracker.instance
        .record('POST ${ApiEndpoints.mockTestSubmit(attemptId)}');
    final response = await _client.dio.post(
      ApiEndpoints.mockTestSubmit(attemptId),
      data: {
        'timeSpentSeconds': timeSpentSeconds,
        'timedOut': timedOut,
        'answers': answers,
      },
    );
    final data =
        (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
    return MockTestAttemptModel.fromJson(data);
  }

  Future<MockTestAttemptModel> _submitSheetTopicTestRemote({
    required int attemptId,
    required int timeSpentSeconds,
    required List<Map<String, dynamic>> answers,
    bool timedOut = false,
  }) async {
    ApiCallTracker.instance.record('POST ${ApiEndpoints.sheetTopicSubmit}');
    final response = await _client.dio.post(
      ApiEndpoints.sheetTopicSubmit,
      data: {
        'attemptId': attemptId,
        'timeSpentSeconds': timeSpentSeconds,
        'timedOut': timedOut,
        'answers': answers,
      },
    );
    final data =
        (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
    return MockTestAttemptModel.fromJson(data);
  }

  Future<MockTestAttemptModel> getAttempt(int attemptId,
      {bool review = false}) async {
    try {
      final response = await _client.dio.get(
        ApiEndpoints.mockTestAttempt(attemptId),
        queryParameters: review ? {'review': true} : null,
      );
      final data = (response.data as Map<String, dynamic>)['data']
          as Map<String, dynamic>;
      final result = MockTestAttemptModel.fromJson(data);
      if (result.isCompleted) {
        await _cacheLatestTopicResult(result);
      }
      return result;
    } catch (e) {
      try {
        final sheetResult = await _getSheetAttemptRemote(attemptId);
        await _cacheLatestTopicResult(sheetResult);
        return sheetResult;
      } catch (_) {}
      final cached = _findCachedAttempt(attemptId);
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<MockTestAttemptModel> _getSheetAttemptRemote(int attemptId) async {
    final endpoint = ApiEndpoints.sheetTopicResult(attemptId);
    ApiCallTracker.instance.record('GET $endpoint');
    final response = await _client.dio.get(endpoint);
    final data =
        (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
    return MockTestAttemptModel.fromJson(data);
  }

  MockTestAttemptModel? _findCachedAttempt(int attemptId) {
    final keys = _store.keysStartingWith(
      LocalStore.latestTopicMockResultPrefix,
    );
    for (final key in keys) {
      final data = _store.getJson(key);
      if (data == null) continue;
      final result = MockTestAttemptModel.fromJson(data);
      if (result.id == attemptId) return result;
    }
    return null;
  }

  Future<List<MockTestAttemptModel>> getAttempts(int topicId) async {
    final response =
        await _client.dio.get(ApiEndpoints.mockTestAttempts(topicId));
    final list =
        (response.data as Map<String, dynamic>)['data'] as List<dynamic>;
    final attempts = list
        .map((e) => MockTestAttemptModel.fromJson(e as Map<String, dynamic>))
        .toList();
    for (final attempt in attempts) {
      if (attempt.isCompleted) {
        await _cacheLatestTopicResult(attempt);
      }
    }
    return attempts;
  }

  Future<MockTestPerformanceModel?> getPerformanceCached() async {
    final data = _store.getJson(LocalStore.mockPerformanceKey);
    if (data == null) return null;
    return MockTestPerformanceModel.fromJson(data);
  }

  Future<MockTestPerformanceModel> getPerformance(
      {bool forceRemote = false}) async {
    if (!forceRemote) {
      final cached = await getPerformanceCached();
      if (cached != null) return cached;
      throw StateError('Performance not cached. Sync when online.');
    }
    ApiCallTracker.instance.record('GET ${ApiEndpoints.mockTestPerformance}');
    final response = await _client.dio.get(ApiEndpoints.mockTestPerformance);
    final data =
        (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
    await _store.putJson(LocalStore.mockPerformanceKey, data);
    return MockTestPerformanceModel.fromJson(data);
  }
}
