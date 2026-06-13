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

class AuthVerifyEmailOtpRequested extends AuthEvent {
  final String email;
  final String otp;
  final String password;
  const AuthVerifyEmailOtpRequested({
    required this.email,
    required this.otp,
    required this.password,
  });
  @override
  List<Object?> get props => [email, otp];
}

class AuthResendEmailOtpRequested extends AuthEvent {
  final String email;
  const AuthResendEmailOtpRequested({required this.email});
  @override
  List<Object?> get props => [email];
}

class AuthForgotPasswordRequested extends AuthEvent {
  final String email;
  const AuthForgotPasswordRequested({required this.email});
  @override
  List<Object?> get props => [email];
}

class AuthVerifyForgotPasswordOtpRequested extends AuthEvent {
  final String email;
  final String otp;
  const AuthVerifyForgotPasswordOtpRequested({
    required this.email,
    required this.otp,
  });
  @override
  List<Object?> get props => [email, otp];
}

class AuthResetPasswordRequested extends AuthEvent {
  final String email;
  final String otp;
  final String newPassword;
  const AuthResetPasswordRequested({
    required this.email,
    required this.otp,
    required this.newPassword,
  });
  @override
  List<Object?> get props => [email, otp];
}

class AuthLogoutRequested extends AuthEvent {}

class AuthGoogleSignInRequested extends AuthEvent {}

class AuthGoogleSignInWithIdToken extends AuthEvent {
  final String idToken;
  const AuthGoogleSignInWithIdToken(this.idToken);
  @override
  List<Object?> get props => [idToken];
}

class AuthDeleteAccountRequested extends AuthEvent {
  final String? password;
  final String? idToken;
  const AuthDeleteAccountRequested({this.password, this.idToken});
  @override
  List<Object?> get props => [password, idToken];
}

class AuthUserUpdated extends AuthEvent {
  final UserModel user;
  const AuthUserUpdated({required this.user});
  @override
  List<Object?> get props => [user];
}
