import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'topic_model.dart';

/// Full subject detail with chapters, topics and per-user progress.
class SubjectDetailModel extends Equatable {
  final int subjectId;
  final String subjectName;
  final String iconName;
  final String colorCode;
  final int totalTopics;
  final int completedTopics;
  final double completionPercent;
  final double totalStudyHours;
  final List<ChapterDetailModel> chapters;

  const SubjectDetailModel({
    required this.subjectId,
    required this.subjectName,
    required this.iconName,
    required this.colorCode,
    required this.totalTopics,
    required this.completedTopics,
    required this.completionPercent,
    required this.totalStudyHours,
    required this.chapters,
  });

  factory SubjectDetailModel.fromJson(Map<String, dynamic> json) {
    final chapters = (json['chapters'] as List<dynamic>? ?? [])
        .map((c) => ChapterDetailModel.fromJson(c as Map<String, dynamic>))
        .toList()
      ..sort((a, b) {
        return a.orderIndex.compareTo(b.orderIndex);
      });

    return SubjectDetailModel(
      subjectId: (json['subjectId'] as num).toInt(),
      subjectName: json['subjectName'] as String,
      iconName: (json['iconName'] as String?) ?? 'book',
      colorCode: (json['colorCode'] as String?) ?? '#6C63FF',
      totalTopics: (json['totalTopics'] as num?)?.toInt() ?? 0,
      completedTopics: (json['completedTopics'] as num?)?.toInt() ?? 0,
      completionPercent:
          ((json['completionPercent'] as num?) ?? 0.0).toDouble(),
      totalStudyHours: ((json['totalStudyHours'] as num?) ?? 0.0).toDouble(),
      chapters: chapters,
    );
  }

  Color get color {
    try {
      final hex = colorCode.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return const Color(0xFF6C63FF);
    }
  }

  IconData get icon {
    const iconMap = <String, IconData>{
      'calculate': Icons.calculate,
      'science': Icons.science,
      'menu_book': Icons.menu_book,
      'language': Icons.language,
      'public': Icons.public,
      'history_edu': Icons.history_edu,
      'biotech': Icons.biotech,
      'psychology': Icons.psychology,
      'functions': Icons.functions,
      'architecture': Icons.architecture,
      'eco': Icons.eco,
      'book': Icons.book,
    };
    return iconMap[iconName] ?? Icons.book;
  }

  @override
  List<Object?> get props => [subjectId, completedTopics, totalStudyHours];
}

class ChapterDetailModel extends Equatable {
  final int id;
  final String title;
  final String? description;
  final int orderIndex;
  final int totalTopics;
  final int completedTopics;
  final double completionPercent;
  final List<TopicModel> topics;

  const ChapterDetailModel({
    required this.id,
    required this.title,
    this.description,
    required this.orderIndex,
    required this.totalTopics,
    required this.completedTopics,
    required this.completionPercent,
    required this.topics,
  });

  factory ChapterDetailModel.fromJson(Map<String, dynamic> json) {
    final topics = (json['topics'] as List<dynamic>? ?? [])
        .map((t) => TopicModel.fromJson(t as Map<String, dynamic>))
        .toList()
      ..sort((a, b) {
        return a.orderIndex.compareTo(b.orderIndex);
      });

    return ChapterDetailModel(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String,
      description: json['description'] as String?,
      orderIndex: (json['orderIndex'] as num?)?.toInt() ?? 0,
      totalTopics: (json['totalTopics'] as num?)?.toInt() ?? 0,
      completedTopics: (json['completedTopics'] as num?)?.toInt() ?? 0,
      completionPercent:
          ((json['completionPercent'] as num?) ?? 0.0).toDouble(),
      topics: topics,
    );
  }

  @override
  List<Object?> get props => [id, completedTopics];
}
