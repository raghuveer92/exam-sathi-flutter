import 'dart:convert';

import '../../core/local/api_call_tracker.dart';
import '../../core/local/local_store.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../models/mock_test_model.dart';

class MockTestRepository {
  final ApiClient _client;
  final LocalStore _store;

  MockTestRepository({
    required ApiClient client,
    required LocalStore store,
  })  : _client = client,
        _store = store;

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
    ApiCallTracker.instance.record('GET ${ApiEndpoints.mockTestTopicInfo(topicId)}');
    final response = await _client.dio.get(ApiEndpoints.mockTestTopicInfo(topicId));
    final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
    await _store.putString(_store.topicMockInfoKey(topicId), jsonEncode(data));
    return MockTestInfoModel.fromJson(data);
  }

  Future<MockTestAttemptModel> startTest(int topicId) async {
    ApiCallTracker.instance.record('POST ${ApiEndpoints.mockTestStart(topicId)}');
    final response = await _client.dio.post(ApiEndpoints.mockTestStart(topicId));
    final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
    return MockTestAttemptModel.fromJson(data);
  }

  Future<MockTestAttemptModel> submitTest(
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
    }
    ApiCallTracker.instance.record('GET ${ApiEndpoints.mockTestPerformance}');
    final response = await _client.dio.get(ApiEndpoints.mockTestPerformance);
    final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
    await _store.putJson(LocalStore.mockPerformanceKey, data);
    return MockTestPerformanceModel.fromJson(data);
  }
}
