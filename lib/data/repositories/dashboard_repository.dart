import '../models/dashboard_model.dart';
import '../models/exam_model.dart';
import '../models/subject_model.dart';
import '../models/subject_progress_model.dart';
import '../models/user_exam_model.dart';
import '../models/user_model.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';

/// Formats a DateTime to YYYY-MM-DD using local year/month/day fields.
/// Avoids toIso8601String() which can return UTC on Flutter web.
String _fmtLocalDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

class DashboardRepository {
  final ApiClient _client;

  DashboardRepository({required ApiClient client}) : _client = client;

  Future<DashboardModel> getDashboard() async {
    final response = await _client.dio.get(ApiEndpoints.dashboard);
    final data = response.data['data'] as Map<String, dynamic>;
    return DashboardModel.fromJson(data);
  }

  Future<List<UserExamModel>> getMyExams() async {
    final response = await _client.dio.get(ApiEndpoints.myExams);
    final list = response.data['data'] as List<dynamic>;
    return list.map((e) => UserExamModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<UserModel> addMyExam({required int examId, DateTime? examDate}) async {
    final response = await _client.dio.post(
      ApiEndpoints.myExams,
      data: {
        'examId': examId,
        if (examDate != null) 'examDate': _fmtLocalDate(examDate),
      },
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

  Future<UserModel> setActiveMyExam(int userExamId) async {
    final response = await _client.dio.patch(ApiEndpoints.setActiveMyExam(userExamId));
    return UserModel.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  Future<UserModel> deleteMyExam(int userExamId) async {
    final response = await _client.dio.delete(ApiEndpoints.deleteMyExam(userExamId));
    return UserModel.fromJson(response.data['data'] as Map<String, dynamic>);
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

  Future<List<SubjectProgressModel>> getSubjectProgressByExam(int examId) async {
    final response = await _client.dio.get(ApiEndpoints.subjectProgress(examId));
    final list = response.data['data'] as List<dynamic>;
    return list
        .map((e) => SubjectProgressModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
