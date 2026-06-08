import 'package:equatable/equatable.dart';
import 'subject_progress_model.dart';
import 'user_model.dart';
import 'user_exam_model.dart';

class DashboardModel extends Equatable {
  final UserModel user;
  final int studyStreakDays;
  final double overallCompletionPercent;
  final double totalEstimatedHours;
  final int totalTopics;
  final int completedTopics;
  final int remainingTopics;
  final double todayHours;
  final int todayTopicsCompleted;
  final int? estimatedDaysToComplete;
  final List<SubjectProgressModel> subjectProgress;
  final List<UserExamModel> myExams;
  final List<DailyLogModel> weeklyLogs;

  const DashboardModel({
    required this.user,
    required this.studyStreakDays,
    required this.overallCompletionPercent,
    this.totalEstimatedHours = 0.0,
    required this.totalTopics,
    required this.completedTopics,
    required this.remainingTopics,
    this.todayHours = 0.0,
    this.todayTopicsCompleted = 0,
    this.estimatedDaysToComplete,
    this.subjectProgress = const [],
    this.myExams = const [],
    this.weeklyLogs = const [],
  });

  factory DashboardModel.fromJson(Map<String, dynamic> json) => DashboardModel(
        user: UserModel.fromJson(json['user'] as Map<String, dynamic>),
        studyStreakDays: (json['studyStreakDays'] as num?)?.toInt() ?? 0,
        overallCompletionPercent:
            ((json['overallCompletionPercent'] as num?) ?? 0.0).toDouble(),
        totalEstimatedHours:
            ((json['totalEstimatedHours'] as num?) ?? 0.0).toDouble(),
        totalTopics: (json['totalTopics'] as num?)?.toInt() ?? 0,
        completedTopics: (json['completedTopics'] as num?)?.toInt() ?? 0,
        remainingTopics: (json['remainingTopics'] as num?)?.toInt() ?? 0,
        todayHours: ((json['todayHours'] as num?) ?? 0.0).toDouble(),
        todayTopicsCompleted: (json['todayTopicsCompleted'] as num?)?.toInt() ?? 0,
        estimatedDaysToComplete: (json['estimatedDaysToComplete'] as num?)?.toInt(),
        subjectProgress: (json['subjectProgress'] as List<dynamic>?)
                ?.map((e) =>
                    SubjectProgressModel.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        myExams: (json['myExams'] as List<dynamic>?)
            ?.map((e) => UserExamModel.fromJson(e as Map<String, dynamic>))
            .toList() ??
          [],
        weeklyLogs: (json['weeklyLogs'] as List<dynamic>?)
                ?.map((e) => DailyLogModel.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );

  @override
  List<Object?> get props => [
        user.selectedExamId,
        user.selectedExamName,
        overallCompletionPercent,
        completedTopics,
        totalTopics,
        remainingTopics,
        studyStreakDays,
        subjectProgress,
        myExams,
        todayHours,
        todayTopicsCompleted,
        weeklyLogs,
      ];

  DashboardModel copyWith({UserModel? user, List<UserExamModel>? myExams}) =>
      DashboardModel(
        user: user ?? this.user,
        studyStreakDays: studyStreakDays,
        overallCompletionPercent: overallCompletionPercent,
        totalEstimatedHours: totalEstimatedHours,
        totalTopics: totalTopics,
        completedTopics: completedTopics,
        remainingTopics: remainingTopics,
        todayHours: todayHours,
        todayTopicsCompleted: todayTopicsCompleted,
        estimatedDaysToComplete: estimatedDaysToComplete,
        subjectProgress: subjectProgress,
        myExams: myExams ?? this.myExams,
        weeklyLogs: weeklyLogs,
      );
}

class DailyLogModel extends Equatable {
  final String studyDate;
  final double hoursStudied;
  final int topicsCompleted;

  const DailyLogModel({
    required this.studyDate,
    required this.hoursStudied,
    required this.topicsCompleted,
  });

  factory DailyLogModel.fromJson(Map<String, dynamic> json) => DailyLogModel(
        studyDate: json['studyDate'] as String,
        hoursStudied: ((json['hoursStudied'] as num?) ?? 0.0).toDouble(),
        topicsCompleted: (json['topicsCompleted'] as num?)?.toInt() ?? 0,
      );

  @override
  List<Object?> get props => [studyDate, hoursStudied];
}
