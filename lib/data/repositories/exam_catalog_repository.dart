import '../models/exam_catalog_model.dart';
import '../models/exam_model.dart';
import '../models/user_model.dart';
import '../../core/local/api_call_tracker.dart';
import '../../core/local/local_store.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';

class ExamCatalogRepository {
  final ApiClient _client;
  final LocalStore _store;

  ExamCatalogRepository({
    required ApiClient client,
    required LocalStore store,
  })  : _client = client,
        _store = store;

  Future<ExamCatalogModel?> getCatalogCached() async {
    final data = _store.getJson(LocalStore.catalogKey);
    if (data == null) return null;
    return ExamCatalogModel.fromJson(data);
  }

  Future<ExamCatalogModel> getCatalog({bool forceRemote = false}) async {
    if (!forceRemote) {
      final cached = await getCatalogCached();
      if (cached != null) return cached;
    }
    ApiCallTracker.instance.record('GET ${ApiEndpoints.examCatalog}');
    final response = await _client.dio.get(ApiEndpoints.examCatalog);
    final data = response.data['data'] as Map<String, dynamic>;
    await _store.putJson(LocalStore.catalogKey, data);
    return ExamCatalogModel.fromJson(data);
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
