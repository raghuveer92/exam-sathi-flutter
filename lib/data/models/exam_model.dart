import 'package:equatable/equatable.dart';

class ExamModel extends Equatable {
  final int id;
  final String name;
  final String? description;
  final String? shortDescription;
  final int? categoryId;
  final String? categoryName;
  final String? code;
  final String? iconUrl;
  final String? bannerUrl;
  final String? colorCode;
  final String? difficultyLevel;
  final bool featured;
  final bool popular;
  final bool isActive;
  final int subjectCount;

  const ExamModel({
    required this.id,
    required this.name,
    this.description,
    this.shortDescription,
    this.categoryId,
    this.categoryName,
    this.code,
    this.iconUrl,
    this.bannerUrl,
    this.colorCode,
    this.difficultyLevel,
    this.featured = false,
    this.popular = false,
    this.isActive = true,
    this.subjectCount = 0,
  });

  factory ExamModel.fromJson(Map<String, dynamic> json) => ExamModel(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String,
        description: json['description'] as String?,
        shortDescription: json['shortDescription'] as String?,
        categoryId: (json['categoryId'] as num?)?.toInt(),
        categoryName: json['categoryName'] as String?,
        code: json['code'] as String?,
        iconUrl: json['iconUrl'] as String?,
        bannerUrl: json['bannerUrl'] as String?,
        colorCode: json['colorCode'] as String?,
        difficultyLevel: json['difficultyLevel'] as String?,
        featured: json['featured'] as bool? ?? false,
        popular: json['popular'] as bool? ?? false,
        isActive: (json['isActive'] as bool?) ?? true,
        subjectCount: (json['subjectCount'] as num?)?.toInt() ?? 0,
      );

  String get cardSubtitle =>
      shortDescription ?? description ?? categoryName ?? 'Exam preparation';

  @override
  List<Object?> get props => [id, name, code];
}
