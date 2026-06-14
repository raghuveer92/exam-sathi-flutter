import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:get_it/get_it.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/local/local_store.dart';
import '../../../core/onboarding/onboarding_wizard_store.dart';
import '../../../core/sync/offline_queue_service.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/progress_repository.dart';
import '../../../presentation/blocs/dashboard/dashboard_bloc.dart';

part 'auth_event.dart';
part 'auth_state.dart';

const _isIntegrationTest = bool.fromEnvironment('INTEGRATION_TEST');

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _authRepository;

  AuthBloc({required AuthRepository authRepository})
      : _authRepository = authRepository,
        super(AuthInitial()) {
    on<AuthCheckRequested>(_onCheckRequested);
    on<AuthLoginRequested>(_onLoginRequested);
    on<AuthRegisterRequested>(_onRegisterRequested);
    on<AuthVerifyEmailOtpRequested>(_onVerifyEmailOtpRequested);
    on<AuthResendEmailOtpRequested>(_onResendEmailOtpRequested);
    on<AuthForgotPasswordRequested>(_onForgotPasswordRequested);
    on<AuthVerifyForgotPasswordOtpRequested>(_onVerifyForgotPasswordOtpRequested);
    on<AuthResetPasswordRequested>(_onResetPasswordRequested);
    on<AuthLogoutRequested>(_onLogoutRequested);
    on<AuthGoogleSignInRequested>(_onGoogleSignInRequested);
    on<AuthGoogleSignInWithIdToken>(_onGoogleSignInWithIdToken);
    on<AuthDeleteAccountRequested>(_onDeleteAccountRequested);
    on<AuthUserUpdated>((event, emit) => emit(AuthAuthenticated(user: event.user)));
  }

  Future<void> _onCheckRequested(
    AuthCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    if (_isIntegrationTest && state is AuthAuthenticated) {
      return;
    }

    emit(AuthLoading());

    final hasToken = await _authRepository.isLoggedIn();
    if (!hasToken) {
      emit(AuthUnauthenticated());
      return;
    }

    final cached = await _authRepository.restoreSession();
    if (cached != null) {
      if (cached.needsEmailVerification) {
        await _endSession(emit);
        return;
      }
      await _ensureOfflineContentFlag();
      _emitAuthenticated(emit, cached, isOfflineSession: true);
    }

    try {
      final user = await _authRepository.getMe();
      if (user.needsEmailVerification) {
        await _endSession(emit);
        return;
      }
      _emitAuthenticated(emit, user, isOfflineSession: false);
      await _ensureOfflineContentFlag();
    } catch (e) {
      if (cached != null) return;
      final fallback = await _authRepository.restoreSession();
      if (fallback != null) {
        _emitAuthenticated(emit, fallback, isOfflineSession: true);
        return;
      }
      if (e is DioException &&
          (e.type == DioExceptionType.connectionError ||
              e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.receiveTimeout)) {
        emit(const AuthError(
            message: 'No internet. Connect once to complete setup.'));
        return;
      }
      emit(AuthUnauthenticated());
    }
  }

  void _emitAuthenticated(
    Emitter<AuthState> emit,
    UserModel user, {
    required bool isOfflineSession,
  }) {
    final current = state;
    if (current is AuthAuthenticated &&
        current.isOfflineSession == isOfflineSession &&
        current.user.id == user.id &&
        current.user.hasSelectedExam == user.hasSelectedExam &&
        current.user.hasExamGoal == user.hasExamGoal) {
      return;
    }
    emit(AuthAuthenticated(user: user, isOfflineSession: isOfflineSession));
  }

  /// Keeps [initialDownloadComplete] in sync with local cache — never clears it.
  Future<void> _ensureOfflineContentFlag() async {
    final store = GetIt.I<LocalStore>();
    if (store.isInitialDownloadComplete()) return;

    if (GetIt.I<ProgressRepository>().hasOfflineStudyContent()) {
      await store.markInitialDownloadComplete();
    }
  }

  Future<void> _onLoginRequested(
    AuthLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final data = await _authRepository.login(event.email, event.password);
      final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
      await _ensureOfflineContentFlag();
      emit(AuthAuthenticated(user: user));
    } catch (e) {
      final message = _parseError(e);
      if (_isEmailVerificationRequired(message)) {
        emit(AuthRegistrationPending(
          email: event.email.trim(),
          fullName: _displayNameFromEmail(event.email),
          password: event.password,
        ));
        return;
      }
      emit(AuthError(message: message));
    }
  }

  Future<void> _onRegisterRequested(
    AuthRegisterRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final data = await _authRepository.register(
        fullName: event.fullName,
        email: event.email,
        password: event.password,
        phone: event.phone,
      );
      emit(AuthRegistrationPending(
        email: data['email'] as String? ?? event.email,
        fullName: data['fullName'] as String? ?? event.fullName,
        password: event.password,
      ));
    } catch (e) {
      emit(AuthError(message: _parseError(e)));
    }
  }

  Future<void> _onVerifyEmailOtpRequested(
    AuthVerifyEmailOtpRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      await _authRepository.verifyEmailOtp(event.email, event.otp);
      final data = await _authRepository.login(event.email, event.password);
      final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
      emit(AuthAuthenticated(user: user));
    } catch (e) {
      emit(AuthError(message: _parseError(e)));
    }
  }

  Future<void> _onResendEmailOtpRequested(
    AuthResendEmailOtpRequested event,
    Emitter<AuthState> emit,
  ) async {
    final previous = state;
    try {
      await _authRepository.resendEmailOtp(event.email);
      if (previous is AuthRegistrationPending) {
        emit(previous);
      }
    } catch (e) {
      emit(AuthError(message: _parseError(e)));
    }
  }

  Future<void> _onForgotPasswordRequested(
    AuthForgotPasswordRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      await _authRepository.forgotPassword(event.email);
      emit(AuthForgotPasswordPending(email: event.email));
    } catch (e) {
      emit(AuthError(message: _parseError(e)));
    }
  }

  Future<void> _onVerifyForgotPasswordOtpRequested(
    AuthVerifyForgotPasswordOtpRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      await _authRepository.verifyForgotPasswordOtp(event.email, event.otp);
      emit(AuthForgotPasswordOtpVerified(email: event.email, otp: event.otp));
    } catch (e) {
      emit(AuthError(message: _parseError(e)));
    }
  }

  Future<void> _onResetPasswordRequested(
    AuthResetPasswordRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      await _authRepository.resetPassword(
        email: event.email,
        otp: event.otp,
        newPassword: event.newPassword,
      );
      emit(AuthUnauthenticated());
    } catch (e) {
      emit(AuthError(message: _parseError(e)));
    }
  }

  Future<void> _onLogoutRequested(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    await _endSession(emit);
  }

  Future<void> _endSession(Emitter<AuthState> emit) async {
    await _authRepository.logout();
    _resetLocalSessionState();
    emit(AuthUnauthenticated());
  }

  /// Clears in-memory UI/session state after Hive is wiped on logout.
  void _resetLocalSessionState() {
    try {
      GetIt.I<OnboardingWizardStore>().reset();
      GetIt.I<OfflineQueueService>().refreshPendingCount();
      GetIt.I<DashboardBloc>().add(DashboardResetRequested());
    } catch (_) {}
  }

  Future<void> _onGoogleSignInRequested(
    AuthGoogleSignInRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final data = await _authRepository.signInWithGoogle();
      final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
      emit(AuthAuthenticated(user: user));
    } catch (e) {
      final message = e.toString();
      if (message.contains('cancelled') || message.contains('canceled')) {
        emit(AuthUnauthenticated());
        return;
      }
      emit(AuthError(message: _parseError(e)));
    }
  }

  Future<void> _onGoogleSignInWithIdToken(
    AuthGoogleSignInWithIdToken event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final data = await _authRepository.signInWithGoogleIdToken(event.idToken);
      final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
      emit(AuthAuthenticated(user: user));
    } catch (e) {
      emit(AuthError(message: _parseError(e)));
    }
  }

  Future<void> _onDeleteAccountRequested(
    AuthDeleteAccountRequested event,
    Emitter<AuthState> emit,
  ) async {
    final previous = state is AuthAuthenticated ? state as AuthAuthenticated : null;
    try {
      await _authRepository.deleteAccount(
        password: event.password,
        idToken: event.idToken,
      );
      emit(AuthUnauthenticated());
    } catch (e) {
      if (previous != null) {
        emit(AuthAuthenticated(
          user: previous.user,
          isOfflineSession: previous.isOfflineSession,
        ));
      } else {
        emit(AuthError(message: _parseError(e)));
      }
    }
  }

  String _parseError(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['message'] is String) {
        return data['message'] as String;
      }
      if (e.message != null && e.message!.isNotEmpty) {
        return e.message!;
      }
    }
    if (e is GoogleSignInException) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return 'Sign in canceled';
      }
      return e.description ?? 'Google Sign-In failed (${e.code.name})';
    }
    if (e is StateError) {
      return e.message;
    }
    final s = e.toString();
    if (s.contains('Exception: ')) return s.split('Exception: ').last.trim();
    if (s.startsWith('Bad state: ')) return s.substring('Bad state: '.length);
    return 'Something went wrong. Please try again.';
  }

  bool _isEmailVerificationRequired(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('verify your email');
  }

  String _displayNameFromEmail(String email) {
    final at = email.indexOf('@');
    if (at <= 0) return 'there';
    final local = email.substring(0, at).trim();
    return local.isNotEmpty ? local : 'there';
  }
}
