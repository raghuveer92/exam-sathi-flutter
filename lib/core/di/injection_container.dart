import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../data/repositories/exam_catalog_repository.dart';
import '../../data/repositories/mock_test_repository.dart';
import '../../data/repositories/progress_repository.dart';
import '../../data/repositories/sync_repository.dart';
import '../local/local_store.dart';
import '../network/api_client.dart';
import '../sync/offline_queue_service.dart';
import '../sync/sync_service.dart';
import '../../presentation/blocs/auth/auth_bloc.dart';
import '../../presentation/blocs/dashboard/dashboard_bloc.dart';

/// Registers all dependencies into the GetIt service locator.
Future<void> setupDependencies() async {
  final sl = GetIt.I;

  await sl.reset();

  final localStore = LocalStore();
  await localStore.init();
  sl.registerSingleton<LocalStore>(localStore);

  sl.registerLazySingleton<Logger>(() => Logger());
  sl.registerLazySingleton<FlutterSecureStorage>(
      () => const FlutterSecureStorage());

  sl.registerLazySingleton<ApiClient>(() => ApiClient(
        storage: sl<FlutterSecureStorage>(),
        logger: sl<Logger>(),
        onUnauthorized: () {
          try {
            sl<AuthBloc>().add(AuthLogoutRequested());
          } catch (_) {}
        },
      ));

  sl.registerLazySingleton<SyncRepository>(
      () => SyncRepository(client: sl<ApiClient>()));
  sl.registerLazySingleton<OfflineQueueService>(() => OfflineQueueService(
        store: sl<LocalStore>(),
        syncRepository: sl<SyncRepository>(),
      ));

  sl.registerLazySingleton<AuthRepository>(() => AuthRepository(
        client: sl<ApiClient>(),
        store: sl<LocalStore>(),
      ));
  sl.registerLazySingleton<DashboardRepository>(() => DashboardRepository(
        client: sl<ApiClient>(),
        store: sl<LocalStore>(),
      ));
  sl.registerLazySingleton<ExamCatalogRepository>(() => ExamCatalogRepository(
        client: sl<ApiClient>(),
        store: sl<LocalStore>(),
      ));
  sl.registerLazySingleton<MockTestRepository>(() => MockTestRepository(
        client: sl<ApiClient>(),
        store: sl<LocalStore>(),
      ));
  sl.registerLazySingleton<ProgressRepository>(() => ProgressRepository(
        client: sl<ApiClient>(),
        store: sl<LocalStore>(),
        offlineQueue: sl<OfflineQueueService>(),
      ));

  sl.registerLazySingleton<SyncService>(() => SyncService(
        store: sl<LocalStore>(),
        syncRepository: sl<SyncRepository>(),
        offlineQueue: sl<OfflineQueueService>(),
        dashboardRepository: sl<DashboardRepository>(),
        progressRepository: sl<ProgressRepository>(),
        mockTestRepository: sl<MockTestRepository>(),
        logger: sl<Logger>(),
      )..startConnectivityListener());

  sl.registerLazySingleton<AuthBloc>(
      () => AuthBloc(authRepository: sl<AuthRepository>()));
  sl.registerFactory<DashboardBloc>(() => DashboardBloc(
        repository: sl<DashboardRepository>(),
        syncService: sl<SyncService>(),
        offlineQueue: sl<OfflineQueueService>(),
      ));
}
