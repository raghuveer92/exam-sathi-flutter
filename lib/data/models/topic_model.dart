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
  /// NOT_STARTED | IN_PROGRESS | COMPLETED
  final String status;
  final String? completedAt;
  final String? lastStudiedAt;
  final int totalTestsAttempted;
  final double? masteryScore;
  /// BEGINNER | DEVELOPING | PROFICIENT | MASTERED
  final String? masteryLevel;
  final String testStatus;

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
    this.status = 'NOT_STARTED',
    this.completedAt,
    this.lastStudiedAt,
    this.totalTestsAttempted = 0,
    this.masteryScore,
    this.masteryLevel,
    this.testStatus = 'LOCKED',
  });

  bool get hasAssessment =>
      totalTestsAttempted > 0 && masteryScore != null;

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
        status: (json['status'] as String?) ?? 'NOT_STARTED',
        completedAt: json['completedAt'] as String?,
        lastStudiedAt: json['lastStudiedAt'] as String?,
        totalTestsAttempted:
            (json['totalTestsAttempted'] as num?)?.toInt() ?? 0,
        masteryScore: (json['masteryScore'] as num?)?.toDouble(),
        masteryLevel: json['masteryLevel'] as String?,
        testStatus: (json['testStatus'] as String?) ?? 'LOCKED',
      );

  TopicModel copyWith({
    bool? isCompleted,
    double? actualHours,
    String? status,
    int? totalTestsAttempted,
    double? masteryScore,
    String? masteryLevel,
    String? testStatus,
  }) =>
      TopicModel(
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
        status: status ?? this.status,
        completedAt: completedAt,
        lastStudiedAt: lastStudiedAt,
        totalTestsAttempted: totalTestsAttempted ?? this.totalTestsAttempted,
        masteryScore: masteryScore ?? this.masteryScore,
        masteryLevel: masteryLevel ?? this.masteryLevel,
        testStatus: testStatus ?? this.testStatus,
      );

  @override
  List<Object?> get props => [
        id,
        title,
        isCompleted,
        status,
        actualHours,
        totalTestsAttempted,
        masteryScore,
        masteryLevel,
      ];
}
