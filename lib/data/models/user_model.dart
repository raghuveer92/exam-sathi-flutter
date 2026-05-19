import 'package:equatable/equatable.dart';

class UserModel extends Equatable {
  final int id;
  final String email;
  final String fullName;
  final String? phone;
  final String? avatarUrl;
  final int? selectedExamId;
  final String? selectedExamName;
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
        studyStreakDays: (json['studyStreakDays'] as num?)?.toInt() ?? 0,
        isActive: (json['isActive'] as bool?) ?? true,
        roles: (json['roles'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
      );

  bool get isAdmin => roles.contains('ROLE_ADMIN');
  bool get hasSelectedExam => selectedExamId != null;

  String get firstName => fullName.split(' ').first;

  @override
  List<Object?> get props => [id, email, fullName, selectedExamId, studyStreakDays];
}
