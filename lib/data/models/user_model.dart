import 'package:equatable/equatable.dart';

class UserModel extends Equatable {
  final int id;
  final String email;
  final String fullName;
  final String? phone;
  final String? avatarUrl;
  final int? selectedExamId;
  final String? selectedExamName;
  final String? examDate;           // ISO date: 2027-03-15
  final String? syllabusTargetDate; // ISO date: 2027-02-13
  final double? dailyTargetHours;
  final double? weeklyTargetHours;
  final int? daysUntilExam;
  final int studyStreakDays;
  final bool isActive;
  final List<String> roles;

  const UserModel({
    required this.id,
    required this.email,
    required this.fullName,
    this.phone,
    this.avatarUrl,
    this.selectedExamId,
    this.selectedExamName,
    this.examDate,
    this.syllabusTargetDate,
    this.dailyTargetHours,
    this.weeklyTargetHours,
    this.daysUntilExam,
    this.studyStreakDays = 0,
    this.isActive = true,
    this.roles = const [],
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: (json['id'] as num).toInt(),
        email: json['email'] as String,
        fullName: json['fullName'] as String,
        phone: json['phone'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
        selectedExamId: (json['selectedExamId'] as num?)?.toInt(),
        selectedExamName: json['selectedExamName'] as String?,
        examDate: json['examDate'] as String?,
        syllabusTargetDate: json['syllabusTargetDate'] as String?,
        dailyTargetHours: (json['dailyTargetHours'] as num?)?.toDouble(),
        weeklyTargetHours: (json['weeklyTargetHours'] as num?)?.toDouble(),
        daysUntilExam: (json['daysUntilExam'] as num?)?.toInt(),
        studyStreakDays: (json['studyStreakDays'] as num?)?.toInt() ?? 0,
        isActive: (json['isActive'] as bool?) ?? true,
        roles: (json['roles'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
      );

  bool get isAdmin => roles.contains('ROLE_ADMIN');
  bool get hasSelectedExam => selectedExamId != null;
  bool get hasExamGoal => examDate != null;

  String get firstName => fullName.split(' ').first;

  UserModel copyWith({
    int? selectedExamId,
    String? selectedExamName,
    String? examDate,
    String? syllabusTargetDate,
    double? dailyTargetHours,
    double? weeklyTargetHours,
    int? daysUntilExam,
  }) => UserModel(
        id: id,
        email: email,
        fullName: fullName,
        phone: phone,
        avatarUrl: avatarUrl,
        selectedExamId: selectedExamId ?? this.selectedExamId,
        selectedExamName: selectedExamName ?? this.selectedExamName,
        examDate: examDate ?? this.examDate,
        syllabusTargetDate: syllabusTargetDate ?? this.syllabusTargetDate,
        dailyTargetHours: dailyTargetHours ?? this.dailyTargetHours,
        weeklyTargetHours: weeklyTargetHours ?? this.weeklyTargetHours,
        daysUntilExam: daysUntilExam ?? this.daysUntilExam,
        studyStreakDays: studyStreakDays,
        isActive: isActive,
        roles: roles,
      );

  @override
  List<Object?> get props => [id, email, fullName, selectedExamId, examDate, studyStreakDays];
}
