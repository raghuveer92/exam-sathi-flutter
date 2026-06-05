import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../data/models/user_model.dart';
import '../../../data/repositories/auth_repository.dart';

part 'auth_event.dart';
part 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _authRepository;

  AuthBloc({required AuthRepository authRepository})
      : _authRepository = authRepository,
        super(AuthInitial()) {
    on<AuthCheckRequested>(_onCheckRequested);
    on<AuthLoginRequested>(_onLoginRequested);
    on<AuthRegisterRequested>(_onRegisterRequested);
    on<AuthLogoutRequested>(_onLogoutRequested);
    on<AuthUserUpdated>((event, emit) => emit(AuthAuthenticated(user: event.user)));
  }

  Future<void> _onCheckRequested(
    AuthCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    final hasToken = await _authRepository.isLoggedIn();
    if (!hasToken) {
      emit(AuthUnauthenticated());
      return;
    }

    // Offline-first: restore cached profile immediately — no network required.
    final cached = await _authRepository.restoreSession();
    if (cached != null) {
      emit(AuthAuthenticated(user: cached, isOfflineSession: true));
    }

    // Background refresh when online (best-effort).
    try {
      final user = await _authRepository.getMe();
      emit(AuthAuthenticated(user: user, isOfflineSession: false));
    } catch (e) {
      if (cached != null) return;
      if (e is DioException &&
          (e.type == DioExceptionType.connectionError ||
              e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.receiveTimeout)) {
        emit(const AuthError(message: 'No internet. Please connect and try again.'));
        return;
      }
      emit(AuthUnauthenticated());
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
      emit(AuthAuthenticated(user: user));
    } catch (e) {
      emit(AuthError(message: _parseError(e)));
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
      final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
      emit(AuthAuthenticated(user: user));
    } catch (e) {
      emit(AuthError(message: _parseError(e)));
    }
  }

  Future<void> _onLogoutRequested(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    await _authRepository.logout();
    emit(AuthUnauthenticated());
  }

  String _parseError(Object e) {
    if (e is DioException && e.message != null && e.message!.isNotEmpty) {
      return e.message!;
    }
    final s = e.toString();
    if (s.contains('Exception: ')) return s.split('Exception: ').last.trim();
    return 'Something went wrong. Please try again.';
  }
}
