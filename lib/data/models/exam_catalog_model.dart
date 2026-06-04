import 'exam_category_model.dart';
import 'exam_model.dart';

class ExamCatalogModel {
  final List<ExamCategoryModel> categories;
  final List<ExamModel> featuredExams;
  final List<ExamModel> recommendedExams;

  const ExamCatalogModel({
    this.categories = const [],
    this.featuredExams = const [],
    this.recommendedExams = const [],
  });

  factory ExamCatalogModel.fromJson(Map<String, dynamic> json) =>
      ExamCatalogModel(
        categories: (json['categories'] as List<dynamic>?)
                ?.map((e) =>
                    ExamCategoryModel.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        featuredExams: (json['featuredExams'] as List<dynamic>?)
                ?.map((e) => ExamModel.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        recommendedExams: (json['recommendedExams'] as List<dynamic>?)
                ?.map((e) => ExamModel.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}
