import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

class SubjectProgressModel extends Equatable {
  final int subjectId;
  final String subjectName;
  final String iconName;
  final String colorCode;
  final int displayOrder;
  final int totalTopics;
  final int completedTopics;
  final double completionPercent;
  final double totalEstimatedHours;

  const SubjectProgressModel({
    required this.subjectId,
    required this.subjectName,
    required this.iconName,
    required this.colorCode,
    this.displayOrder = 0,
    required this.totalTopics,
    required this.completedTopics,
    required this.completionPercent,
    this.totalEstimatedHours = 0.0,
  });

  factory SubjectProgressModel.fromJson(Map<String, dynamic> json) =>
      SubjectProgressModel(
        subjectId: (json['subjectId'] as num).toInt(),
        subjectName: json['subjectName'] as String,
        iconName: (json['iconName'] as String?) ?? 'book',
        colorCode: (json['colorCode'] as String?) ?? '#6C63FF',
        displayOrder: (json['displayOrder'] as num?)?.toInt() ?? 0,
        totalTopics: (json['totalTopics'] as num?)?.toInt() ?? 0,
        completedTopics: (json['completedTopics'] as num?)?.toInt() ?? 0,
        completionPercent:
            ((json['completionPercent'] as num?) ?? 0.0).toDouble(),
        totalEstimatedHours:
            ((json['totalEstimatedHours'] as num?) ?? 0.0).toDouble(),
      );

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
      'computer': Icons.computer,
    };
    return iconMap[iconName] ?? Icons.book;
  }

  @override
  List<Object?> get props => [subjectId, completionPercent];
}
