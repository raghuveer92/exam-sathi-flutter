import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/firebase/analytics_service.dart';
import '../../presentation/blocs/auth/auth_bloc.dart';
import '../../presentation/screens/auth/login_screen.dart';
import '../../presentation/screens/auth/register_screen.dart';
import '../../presentation/screens/dashboard/dashboard_screen.dart';
import '../../presentation/screens/subjects/subjects_screen.dart';
import '../../presentation/screens/subjects/subject_detail_screen.dart';
import '../../presentation/screens/topics/topic_list_screen.dart';
import '../../presentation/screens/analytics/analytics_screen.dart';
import '../../presentation/screens/profile/profile_screen.dart';
import '../../presentation/screens/profile/my_exams_screen.dart';
import '../../presentation/screens/onboarding/exam_selection_screen.dart';
import '../../presentation/screens/onboarding/exam_goal_setup_screen.dart';
import '../../data/models/exam_model.dart';
import '../../presentation/screens/main/main_scaffold.dart';
import '../../presentation/screens/splash/splash_screen.dart';

/// Bridges a Bloc stream into a [ChangeNotifier] so GoRouter can
/// re-evaluate its redirect whenever auth state changes.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Stream<dynamic> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }
  late final StreamSubscription<dynamic> _sub;
  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

class AppRouter {
  static GoRouter createRouter(AuthBloc authBloc) {
    final rootNavigatorKey = GlobalKey<NavigatorState>();
    final shellNavigatorKey = GlobalKey<NavigatorState>();
    return _buildRouter(authBloc, rootNavigatorKey, shellNavigatorKey);
  }

  static GoRouter _buildRouter(
    AuthBloc authBloc,
    GlobalKey<NavigatorState> rootNavigatorKey,
    GlobalKey<NavigatorState> shellNavigatorKey,
  ) =>
      GoRouter(
    navigatorKey: rootNavigatorKey,
    observers: [AnalyticsService.observer],
    initialLocation: '/splash',
    refreshListenable: _AuthRefreshNotifier(authBloc.stream),
    redirect: (context, state) {
      final authState = context.read<AuthBloc>().state;
      final loc = state.matchedLocation;
      final isSplash = loc == '/splash';
      final isSelectExam = loc == '/select-exam';
      final isMyExams = loc == '/my-exams';
      final isOnboardingMyExams =
          isMyExams && state.uri.queryParameters['onboarding'] == '1';
      final isChangeExamFlow = isSelectExam && state.uri.queryParameters['change'] == '1';

      if (authState is AuthLoading && !isSplash) return '/splash';
      if (authState is AuthInitial && !isSplash) return '/splash';

      if (authState is AuthAuthenticated) {
        final user = authState.user;
        // From splash/login/register — guide to the right step
        if (isSplash || loc == '/login' || loc == '/register') {
          if (!user.hasExamGoal) return '/my-exams?onboarding=1';
          return '/home';
        }
        // Advance forward when setup step completes
        if (user.hasSelectedExam && user.hasExamGoal &&
            (loc == '/exam-goal' ||
                (isSelectExam && !isChangeExamFlow) ||
                isOnboardingMyExams)) {
          return '/home';
        }
        if (!user.hasSelectedExam && loc == '/exam-goal') {
          return '/my-exams?onboarding=1';
        }
        if (!user.hasExamGoal && isSelectExam && !isChangeExamFlow) {
          return '/my-exams?onboarding=1';
        }
        // Block dashboard if setup incomplete
        if (!user.hasSelectedExam && !isOnboardingMyExams) {
          return '/my-exams?onboarding=1';
        }
        if (user.hasSelectedExam && !user.hasExamGoal &&
            loc != '/exam-goal' &&
            !isOnboardingMyExams) {
          return '/my-exams?onboarding=1';
        }
      }

      if (authState is AuthUnauthenticated) {
        if (!loc.startsWith('/login') &&
            !loc.startsWith('/register') &&
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
      GoRoute(
        path: '/select-exam',
        builder: (_, state) => ExamSelectionScreen(
          isChangeMode: state.uri.queryParameters['change'] == '1',
        ),
      ),
      GoRoute(
        path: '/exam-goal',
        builder: (_, state) => ExamGoalSetupScreen(
          exam: state.extra as ExamModel?,
        ),
      ),

      // Main scaffold with bottom navigation
      ShellRoute(
        navigatorKey: shellNavigatorKey,
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
          GoRoute(
            path: '/my-exams',
            builder: (_, state) => MyExamsScreen(
              isOnboarding: state.uri.queryParameters['onboarding'] == '1',
            ),
          ),
        ],
      ),
    ],
  );
}
