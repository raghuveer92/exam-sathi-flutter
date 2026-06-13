part of 'auth_bloc.dart';

abstract class AuthState extends Equatable {
  const AuthState();
  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

class AuthAuthenticated extends AuthState {
  final UserModel user;
  final bool isOfflineSession;
  const AuthAuthenticated({
    required this.user,
    this.isOfflineSession = false,
  });
  @override
  List<Object?> get props => [user, isOfflineSession];
}

class AuthUnauthenticated extends AuthState {}

class AuthRegistrationPending extends AuthState {
  final String email;
  final String fullName;
  final String password;
  const AuthRegistrationPending({
    required this.email,
    required this.fullName,
    required this.password,
  });
  @override
  List<Object?> get props => [email, fullName];
}

class AuthForgotPasswordPending extends AuthState {
  final String email;
  const AuthForgotPasswordPending({required this.email});
  @override
  List<Object?> get props => [email];
}

class AuthForgotPasswordOtpVerified extends AuthState {
  final String email;
  final String otp;
  const AuthForgotPasswordOtpVerified({
    required this.email,
    required this.otp,
  });
  @override
  List<Object?> get props => [email, otp];
}

class AuthError extends AuthState {
  final String message;
  const AuthError({required this.message});
  @override
  List<Object?> get props => [message];
}
