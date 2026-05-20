import '../models/dashboard_model.dart';
import '../models/exam_model.dart';
import '../models/subject_model.dart';
import '../models/user_model.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';

class DashboardRepository {
  final ApiClient _client;

  DashboardRepository({required ApiClient client}) : _client = client;

  Future<DashboardModel> getDashboard() async {
    final response = await _client.dio.get(ApiEndpoints.dashboard);
    return DashboardModel.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  Future<List<ExamModel>> getExams() async {
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
  }) async {
    final body = {
      'examDate': examDate.toIso8601String().substring(0, 10),
      if (syllabusTargetDate != null)
        'syllabusTargetDate': syllabusTargetDate.toIso8601String().substring(0, 10),
    };
    final response = await _client.dio.post(ApiEndpoints.examGoal, data: body);
    return UserModel.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  Future<void> updateStudyHours(double dailyTargetHours) async {
    await _client.dio.patch(
      ApiEndpoints.studyHours,
      data: {'dailyTargetHours': dailyTargetHours},
    );
  }

  Future<List<SubjectModel>> getSubjectsByExam(int examId) async {
    final response = await _client.dio.get(ApiEndpoints.subjectsByExam(examId));
    final list = response.data['data'] as List<dynamic>;
    return list.map((e) => SubjectModel.fromJson(e as Map<String, dynamic>)).toList();
  }
}
