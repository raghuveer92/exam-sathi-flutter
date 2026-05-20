import '../models/subject_detail_model.dart';
import '../models/topic_model.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';

class ProgressRepository {
  final ApiClient _client;

  ProgressRepository({required ApiClient client}) : _client = client;

  Future<List<TopicModel>> getTopicsByChapter(int chapterId) async {
    final response = await _client.dio.get(ApiEndpoints.topicsByChapter(chapterId));
    final list = response.data['data'] as List<dynamic>;
    return list.map((e) => TopicModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<SubjectDetailModel> getSubjectDetail(int subjectId) async {
    final response = await _client.dio.get(ApiEndpoints.subjectDetail(subjectId));
    return SubjectDetailModel.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  Future<void> markTopicComplete({
    required int topicId,
    required bool isCompleted,
    double actualHours = 0.0,
  }) async {
    await _client.dio.post(ApiEndpoints.updateProgress, data: {
      'topicId': topicId,
      'isCompleted': isCompleted,
      'actualHours': actualHours,
    });
  }

  Future<void> logStudyHours({
    required String studyDate,
    required double hoursStudied,
    int topicsCompleted = 0,
  }) async {
    await _client.dio.post(ApiEndpoints.logStudy, data: {
      'studyDate': studyDate,
      'hoursStudied': hoursStudied,
      'topicsCompleted': topicsCompleted,
    });
  }
}
