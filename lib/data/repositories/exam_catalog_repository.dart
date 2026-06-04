import '../models/exam_catalog_model.dart';
import '../models/exam_model.dart';
import '../models/user_model.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';

class ExamCatalogRepository {
  final ApiClient _client;

  ExamCatalogRepository({required ApiClient client}) : _client = client;

  Future<ExamCatalogModel> getCatalog() async {
    final response = await _client.dio.get(ApiEndpoints.examCatalog);
    return ExamCatalogModel.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );
  }

  Future<List<ExamModel>> getExamsByCategory(int categoryId) async {
    final response =
        await _client.dio.get(ApiEndpoints.examsByCategory(categoryId));
    final list = response.data['data'] as List<dynamic>;
    return list
        .map((e) => ExamModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ExamModel>> searchExams(String query) async {
    final response = await _client.dio.get(
      ApiEndpoints.examCatalogSearch,
      queryParameters: {'q': query},
    );
    final list = response.data['data'] as List<dynamic>;
    return list
        .map((e) => ExamModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<UserModel> enrollExam({
    required int examId,
    required DateTime examDate,
    DateTime? syllabusTargetDate,
    required double dailyTargetHours,
    required String experienceLevel,
    List<Map<String, dynamic>> subjectSelections = const [],
  }) async {
    final response = await _client.dio.post(
      ApiEndpoints.enrollExam,
      data: {
        'examId': examId,
        'examDate': _fmt(examDate),
        if (syllabusTargetDate != null)
          'syllabusTargetDate': _fmt(syllabusTargetDate),
        'dailyTargetHours': dailyTargetHours,
        'experienceLevel': experienceLevel,
        if (subjectSelections.isNotEmpty) 'subjectSelections': subjectSelections,
      },
    );
    return UserModel.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
