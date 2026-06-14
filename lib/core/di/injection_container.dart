import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';

import '../auth/google_auth_config.dart';
import '../auth/google_auth_service.dart';
import '../local/local_store.dart';
import '../network/api_client.dart';
import '../study/daily_target_calculator.dart';
import '../sync/offline_queue_service.dart';
import '../sync/progress_rebuild_service.dart';
import '../sync/sync_service.dart';
import '../onboarding/onboarding_wizard_store.dart';
import '../testing/integration_test_reset.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../data/repositories/exam_catalog_repository.dart';
import '../../data/repositories/mock_test_repository.dart';
import '../../data/repositories/progress_repository.dart';
import '../../data/repositories/sync_repository.dart';
import '../../presentation/blocs/auth/auth_bloc.dart';
import '../../presentation/blocs/dashboard/dashboard_bloc.dart';

/// Registers all dependencies into the GetIt service locator.
Future<void> setupDependencies() async {
  final sl = GetIt.I;

  await sl.reset();

  const isIntegrationTest = bool.fromEnvironment('INTEGRATION_TEST');
  if (isIntegrationTest) {
    await resetIntegrationTestPersistence();
  }

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
  sl.registerLazySingleton<OfflineQueueService>(() {
    final queue = OfflineQueueService(
      store: sl<LocalStore>(),
      syncRepository: sl<SyncRepository>(),
    );
    queue.refreshPendingCount();
    return queue;
  });

  sl.registerLazySingleton<GoogleAuthService>(() => GoogleAuthService());

  // Initialize GIS once at startup so credential events are not missed on web.
  if (kIsWeb && GoogleAuthConfig.isConfigured) {
    await sl<GoogleAuthService>().initialize();
  }

  sl.registerLazySingleton<AuthRepository>(() => AuthRepository(
        client: sl<ApiClient>(),
        store: sl<LocalStore>(),
        googleAuth: sl<GoogleAuthService>(),
      ));
  sl.registerLazySingleton<DashboardRepository>(() => DashboardRepository(
        client: sl<ApiClient>(),
        store: sl<LocalStore>(),
        offlineQueue: sl<OfflineQueueService>(),
      ));
  sl.registerLazySingleton<DailyTargetCalculator>(() => DailyTargetCalculator(
        store: sl<LocalStore>(),
        dashboardRepository: sl<DashboardRepository>(),
      ));
  sl.registerLazySingleton<ProgressRebuildService>(() => ProgressRebuildService(
        store: sl<LocalStore>(),
        dashboardRepository: sl<DashboardRepository>(),
      ));
  sl.registerLazySingleton<ExamCatalogRepository>(() => ExamCatalogRepository(
        client: sl<ApiClient>(),
        store: sl<LocalStore>(),
      ));
  sl.registerLazySingleton<MockTestRepository>(() => MockTestRepository(
        client: sl<ApiClient>(),
        store: sl<LocalStore>(),
        offlineQueue: sl<OfflineQueueService>(),
      ));
  sl.registerLazySingleton<ProgressRepository>(() => ProgressRepository(
        client: sl<ApiClient>(),
        store: sl<LocalStore>(),
        offlineQueue: sl<OfflineQueueService>(),
        dashboardRepository: sl<DashboardRepository>(),
        progressRebuildService: sl<ProgressRebuildService>(),
      ));

  sl.registerLazySingleton<SyncService>(() {
    final sync = SyncService(
        store: sl<LocalStore>(),
        syncRepository: sl<SyncRepository>(),
        offlineQueue: sl<OfflineQueueService>(),
        authRepository: sl<AuthRepository>(),
        dashboardRepository: sl<DashboardRepository>(),
        progressRepository: sl<ProgressRepository>(),
        progressRebuildService: sl<ProgressRebuildService>(),
        mockTestRepository: sl<MockTestRepository>(),
        logger: sl<Logger>(),
      );
    sl<OfflineQueueService>().onQueueChanged = sync.scheduleBackgroundSync;
    sync.startConnectivityListener();
    return sync;
  });

  sl.registerLazySingleton<OnboardingWizardStore>(
      () => OnboardingWizardStore());

  sl.registerLazySingleton<AuthBloc>(
      () => AuthBloc(authRepository: sl<AuthRepository>()));
  sl.registerFactory<DashboardBloc>(() => DashboardBloc(
        repository: sl<DashboardRepository>(),
        progressRebuildService: sl<ProgressRebuildService>(),
        dailyTargetCalculator: sl<DailyTargetCalculator>(),
      ));
}
