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
  await FirebaseInitializer.initialize();
  await setupDependencies();
  runApp(const ExamSaathiApp());
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
