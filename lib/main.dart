import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'core/di/injection_container.dart';
import 'core/firebase/analytics_service.dart';
import 'core/firebase/firebase_initializer.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'presentation/blocs/auth/auth_bloc.dart';
import 'presentation/blocs/dashboard/dashboard_bloc.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch all Flutter framework errors and show them on-screen
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  // Catch async errors outside Flutter framework (e.g. during startup)
  PlatformDispatcher.instance.onError = (error, stack) {
    runApp(_CrashScreen(error: '$error', stack: '$stack'));
    return true;
  };

  try {
    await FirebaseInitializer.initialize();
    AnalyticsService.logAppOpen();
    await setupDependencies();
    runApp(const ExamSaathiApp());
  } catch (e, stack) {
    runApp(_CrashScreen(error: '$e', stack: '$stack'));
  }
}


class ExamSaathiApp extends StatefulWidget {
  const ExamSaathiApp({super.key});

  @override
  State<ExamSaathiApp> createState() => _ExamSaathiAppState();
}

class _ExamSaathiAppState extends State<ExamSaathiApp> {
  late final AuthBloc _authBloc;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _authBloc = GetIt.I<AuthBloc>()..add(AuthCheckRequested());
    _router = AppRouter.createRouter(_authBloc);
  }

  @override
  void dispose() {
    // AuthBloc is a GetIt singleton — do not close it here
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _authBloc),
        BlocProvider(create: (_) => GetIt.I<DashboardBloc>()),
      ],
      child: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          // Reset dashboard data on logout so next login fetches fresh data
          if (state is AuthUnauthenticated) {
            context.read<DashboardBloc>().add(DashboardResetRequested());
            AnalyticsService.logLogout();
          }
        },
        child: MaterialApp.router(
          title: 'ExamSaathi',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          routerConfig: _router,
        ),
      ),
    );
  }
}

// ── Crash screen shown when startup fails ────────────────────────────────────
class _CrashScreen extends StatelessWidget {
  final String error;
  final String stack;
  const _CrashScreen({required this.error, required this.stack});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF1A1A2E),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.bug_report, color: Colors.redAccent, size: 48),
                const SizedBox(height: 12),
                const Text(
                  'App crashed on startup',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade900.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    error,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  stack,
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
