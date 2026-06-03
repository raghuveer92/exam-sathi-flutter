import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../models/mock_test_model.dart';

class MockTestRepository {
  final ApiClient _client;
  MockTestRepository({required ApiClient client}) : _client = client;

  Future<MockTestInfoModel> getTopicInfo(int topicId) async {
    final response = await _client.dio.get(ApiEndpoints.mockTestTopicInfo(topicId));
    final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
    return MockTestInfoModel.fromJson(data);
  }

  Future<MockTestAttemptModel> startTest(int topicId) async {
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

  Future<MockTestPerformanceModel> getPerformance() async {
    final response = await _client.dio.get(ApiEndpoints.mockTestPerformance);
    final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
    return MockTestPerformanceModel.fromJson(data);
  }
}
