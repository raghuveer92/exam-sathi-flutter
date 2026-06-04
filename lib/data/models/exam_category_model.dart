import 'package:equatable/equatable.dart';

class ExamCategoryModel extends Equatable {
  final int id;
  final String name;
  final String? description;
  final String? icon;
  final int displayOrder;
  final int examCount;

  const ExamCategoryModel({
    required this.id,
    required this.name,
    this.description,
    this.icon,
    this.displayOrder = 0,
    this.examCount = 0,
  });

  factory ExamCategoryModel.fromJson(Map<String, dynamic> json) =>
      ExamCategoryModel(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String,
        description: json['description'] as String?,
        icon: json['icon'] as String?,
        displayOrder: (json['displayOrder'] as num?)?.toInt() ?? 0,
        examCount: (json['examCount'] as num?)?.toInt() ?? 0,
      );

  @override
  List<Object?> get props => [id, name];
}
