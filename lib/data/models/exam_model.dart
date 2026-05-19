import 'package:equatable/equatable.dart';

class ExamModel extends Equatable {
  final int id;
  final String name;
  final String? description;
  final String? code;
  final String? iconUrl;
  final String? colorCode;
  final bool isActive;
  final int subjectCount;

  const ExamModel({
    required this.id,
    required this.name,
    this.description,
    this.code,
    this.iconUrl,
    this.colorCode,
    this.isActive = true,
    this.subjectCount = 0,
  });

  factory ExamModel.fromJson(Map<String, dynamic> json) => ExamModel(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String,
        description: json['description'] as String?,
        code: json['code'] as String?,
        iconUrl: json['iconUrl'] as String?,
        colorCode: json['colorCode'] as String?,
        isActive: (json['isActive'] as bool?) ?? true,
        subjectCount: (json['subjectCount'] as num?)?.toInt() ?? 0,
      );

  @override
  List<Object?> get props => [id, name, code];
}
