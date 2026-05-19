import 'package:equatable/equatable.dart';

class TopicModel extends Equatable {
  final int id;
  final int chapterId;
  final String chapterTitle;
  final String title;
  final String? description;
  final double estimatedHours;
  final String difficultyLevel;
  final int orderIndex;
  final bool isActive;
  final bool isCompleted;
  final double actualHours;

  const TopicModel({
    required this.id,
    required this.chapterId,
    required this.chapterTitle,
    required this.title,
    this.description,
    this.estimatedHours = 1.0,
    this.difficultyLevel = 'MEDIUM',
    this.orderIndex = 0,
    this.isActive = true,
    this.isCompleted = false,
    this.actualHours = 0.0,
  });

  factory TopicModel.fromJson(Map<String, dynamic> json) => TopicModel(
        id: (json['id'] as num).toInt(),
        chapterId: (json['chapterId'] as num).toInt(),
        chapterTitle: (json['chapterTitle'] as String?) ?? '',
        title: json['title'] as String,
        description: json['description'] as String?,
        estimatedHours: ((json['estimatedHours'] as num?) ?? 1.0).toDouble(),
        difficultyLevel: (json['difficultyLevel'] as String?) ?? 'MEDIUM',
        orderIndex: (json['orderIndex'] as num?)?.toInt() ?? 0,
        isActive: (json['isActive'] as bool?) ?? true,
        isCompleted: (json['isCompleted'] as bool?) ?? false,
        actualHours: ((json['actualHours'] as num?) ?? 0.0).toDouble(),
      );

  TopicModel copyWith({bool? isCompleted, double? actualHours}) => TopicModel(
        id: id,
        chapterId: chapterId,
        chapterTitle: chapterTitle,
        title: title,
        description: description,
        estimatedHours: estimatedHours,
        difficultyLevel: difficultyLevel,
        orderIndex: orderIndex,
        isActive: isActive,
        isCompleted: isCompleted ?? this.isCompleted,
        actualHours: actualHours ?? this.actualHours,
      );

  @override
  List<Object?> get props => [id, title, isCompleted];
}
