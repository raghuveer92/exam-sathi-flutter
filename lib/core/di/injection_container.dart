import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../data/repositories/progress_repository.dart';
import '../network/api_client.dart';
import '../../presentation/blocs/auth/auth_bloc.dart';
import '../../presentation/blocs/dashboard/dashboard_bloc.dart';

/// Registers all dependencies into the GetIt service locator.
Future<void> setupDependencies() async {
  final sl = GetIt.I;

  // ── Core ──────────────────────────────────────────────────────────────────
  sl.registerLazySingleton<Logger>(() => Logger());
  sl.registerLazySingleton<FlutterSecureStorage>(
      () => const FlutterSecureStorage());

  sl.registerLazySingleton<ApiClient>(() => ApiClient(
        storage: sl<FlutterSecureStorage>(),
        logger: sl<Logger>(),
        // On 401/403, auto-logout: lazily resolved so no circular dependency
        onUnauthorized: () {
          try {
            sl<AuthBloc>().add(AuthLogoutRequested());
          } catch (_) {}
        },
      ));


  // ── Repositories ──────────────────────────────────────────────────────────
  sl.registerLazySingleton<AuthRepository>(
      () => AuthRepository(client: sl<ApiClient>()));
  sl.registerLazySingleton<DashboardRepository>(
      () => DashboardRepository(client: sl<ApiClient>()));
  sl.registerLazySingleton<ProgressRepository>(
      () => ProgressRepository(client: sl<ApiClient>()));

  // ── BLoCs ─────────────────────────────────────────────────────────────────
  sl.registerLazySingleton<AuthBloc>(
      () => AuthBloc(authRepository: sl<AuthRepository>()));
  sl.registerFactory<DashboardBloc>(
      () => DashboardBloc(repository: sl<DashboardRepository>()));
}
