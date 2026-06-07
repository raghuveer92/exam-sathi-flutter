import 'package:equatable/equatable.dart';

class UserExamModel extends Equatable {
  final int id;
  final int examId;
  final String examName;
  final String? examDate;
  final int? daysLeft;
  final int? totalSubjects;
  final double? progressPercent;
  final double? dailyTargetHours;
  final double? weeklyTargetHours;
  final bool isActive;

  const UserExamModel({
    required this.id,
    required this.examId,
    required this.examName,
    this.examDate,
    this.daysLeft,
    this.totalSubjects,
    this.progressPercent,
    this.dailyTargetHours,
    this.weeklyTargetHours,
    this.isActive = false,
  });

  factory UserExamModel.fromJson(Map<String, dynamic> json) => UserExamModel(
        id: (json['id'] as num).toInt(),
        examId: (json['examId'] as num).toInt(),
        examName: json['examName'] as String,
        examDate: json['examDate'] as String?,
        daysLeft: (json['daysLeft'] as num?)?.toInt(),
        totalSubjects: (json['totalSubjects'] as num?)?.toInt(),
        progressPercent: (json['progressPercent'] as num?)?.toDouble(),
        dailyTargetHours: (json['dailyTargetHours'] as num?)?.toDouble(),
        weeklyTargetHours: (json['weeklyTargetHours'] as num?)?.toDouble(),
        isActive: (json['isActive'] as bool?) ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'examId': examId,
        'examName': examName,
        'examDate': examDate,
        'daysLeft': daysLeft,
        'totalSubjects': totalSubjects,
        'progressPercent': progressPercent,
        'dailyTargetHours': dailyTargetHours,
        'weeklyTargetHours': weeklyTargetHours,
        'isActive': isActive,
      };

  @override
  List<Object?> get props => [id, examId, examName, examDate, isActive, progressPercent];
}
