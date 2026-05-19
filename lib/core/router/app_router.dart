import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../presentation/blocs/auth/auth_bloc.dart';
import '../../presentation/screens/auth/login_screen.dart';
import '../../presentation/screens/auth/register_screen.dart';
import '../../presentation/screens/dashboard/dashboard_screen.dart';
import '../../presentation/screens/subjects/subjects_screen.dart';
import '../../presentation/screens/subjects/subject_detail_screen.dart';
import '../../presentation/screens/topics/topic_list_screen.dart';
import '../../presentation/screens/analytics/analytics_screen.dart';
import '../../presentation/screens/profile/profile_screen.dart';
import '../../presentation/screens/onboarding/exam_selection_screen.dart';
import '../../presentation/screens/main/main_scaffold.dart';
import '../../presentation/screens/splash/splash_screen.dart';

class AppRouter {
  static final _rootNavigatorKey = GlobalKey<NavigatorState>();

  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/splash',
    redirect: (context, state) {
      final authState = context.read<AuthBloc>().state;
      final isSplash = state.matchedLocation == '/splash';

      if (authState is AuthLoading && !isSplash) return '/splash';
      if (authState is AuthAuthenticated) {
        if (isSplash ||
            state.matchedLocation == '/login' ||
            state.matchedLocation == '/register') {
          return '/home';
        }
      }
      if (authState is AuthUnauthenticated) {
        if (!state.matchedLocation.startsWith('/login') &&
            !state.matchedLocation.startsWith('/register') &&
            !isSplash) {
          return '/login';
        }
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/select-exam', builder: (_, __) => const ExamSelectionScreen()),

      // Main scaffold with bottom navigation
      ShellRoute(
        builder: (context, state, child) => MainScaffold(child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const DashboardScreen()),
          GoRoute(
            path: '/subjects',
            builder: (_, __) => const SubjectsScreen(),
            routes: [
              GoRoute(
                path: ':subjectId',
                builder: (_, state) => SubjectDetailScreen(
                  subjectId: int.parse(state.pathParameters['subjectId']!),
                ),
                routes: [
                  GoRoute(
                    path: 'chapter/:chapterId',
                    builder: (_, state) => TopicListScreen(
                      chapterId: int.parse(state.pathParameters['chapterId']!),
                    ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(path: '/study', builder: (_, __) => const DashboardScreen()),
          GoRoute(path: '/analytics', builder: (_, __) => const AnalyticsScreen()),
          GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
        ],
      ),
    ],
  );
}
