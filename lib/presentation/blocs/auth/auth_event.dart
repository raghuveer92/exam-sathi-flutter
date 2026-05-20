part of 'auth_bloc.dart';

abstract class AuthEvent extends Equatable {
  const AuthEvent();
  @override
  List<Object?> get props => [];
}

class AuthCheckRequested extends AuthEvent {}

class AuthLoginRequested extends AuthEvent {
  final String email;
  final String password;
  const AuthLoginRequested({required this.email, required this.password});
  @override
  List<Object?> get props => [email];
}

class AuthRegisterRequested extends AuthEvent {
  final String fullName;
  final String email;
  final String password;
  final String? phone;
  const AuthRegisterRequested({
    required this.fullName,
    required this.email,
    required this.password,
    this.phone,
  });
  @override
  List<Object?> get props => [email, fullName];
}

class AuthLogoutRequested extends AuthEvent {}

/// Locally updates the authenticated user without a network round-trip.
/// Use after mutations (selectExam, setExamGoal) to keep router state in sync.
class AuthUserUpdated extends AuthEvent {
  final UserModel user;
  const AuthUserUpdated({required this.user});
  @override
  List<Object?> get props => [user];
}
