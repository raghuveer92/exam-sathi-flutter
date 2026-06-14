import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/firebase/analytics_service.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/onboarding/onboarding_wizard_store.dart';
import '../../../core/router/app_navigation.dart';
import '../../../data/models/user_exam_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/dashboard_repository.dart';
import '../../../data/repositories/exam_catalog_repository.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/dashboard/dashboard_bloc.dart';
import 'widgets/onboarding_shared_widgets.dart';

/// Screen 3 — confirm enrollment (onboarding).
class OnboardingConfirmScreen extends StatefulWidget {
  const OnboardingConfirmScreen({super.key});

  @override
  State<OnboardingConfirmScreen> createState() =>
      _OnboardingConfirmScreenState();
}

class _OnboardingConfirmScreenState extends State<OnboardingConfirmScreen> {
  final _catalogRepo = GetIt.I<ExamCatalogRepository>();
  final _dashboardRepo = GetIt.I<DashboardRepository>();
  late final OnboardingWizardStore _store;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _store = GetIt.I<OnboardingWizardStore>();
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      _store.bindUser(authState.user.id);
    }
    if (_store.selectedExam == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        AppNavigation.popOrGoIfDifferent(context, '/onboarding/choose-exam');
      });
    }
  }

  Future<void> _confirmEnroll() async {
    final exam = _store.selectedExam;
    if (exam == null) return;

    if (await _dashboardRepo.isExamAlreadyEnrolled(exam.id)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are already enrolled in this exam'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final examDate = _store.resolveExamDate();
      final user = await _catalogRepo.enrollExam(
        examId: exam.id,
        examDate: examDate,
        syllabusTargetDate: examDate.subtract(const Duration(days: 30)),
        experienceLevel: _store.experience,
        subjectSelections: _store.subjectSelections,
      );
      final cachedUser = await _dashboardRepo.applyEnrollmentToCache(user);
      await GetIt.I<AuthRepository>().cacheUser(cachedUser);
      if (!mounted) return;

      AnalyticsService.logExamSelected(examId: exam.id, examName: exam.name);
      context.read<AuthBloc>().add(AuthUserUpdated(user: cachedUser));
      context.read<DashboardBloc>().add(DashboardResetRequested());
      _store.reset();

      UserExamModel? enrolledExam;
      for (final e in cachedUser.userExams) {
        if (e.examId == exam.id) {
          enrolledExam = e;
          break;
        }
      }
      enrolledExam ??=
          cachedUser.userExams.isNotEmpty ? cachedUser.userExams.first : null;
      final enrollmentId = enrolledExam?.id ?? cachedUser.activeUserExamId;
      final userExamIdParam =
          enrollmentId != null ? '&userExamId=$enrollmentId' : '';

      AppNavigation.replaceTo(
        context,
        '/offline-setup?mode=enrollment&redirect=${Uri.encodeComponent('/home')}'
        '&title=${Uri.encodeComponent('Downloading Exam Content')}$userExamIdParam',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(apiErrorMessage(e)),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _handleBack() {
    if (_loading) return;
    AppNavigation.popOrGoIfDifferent(context, '/onboarding/set-goal');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final exam = _store.selectedExam;
        if (exam == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            _handleBack();
          },
          child: Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
              title: const Text('Confirm Setup'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _loading ? null : _handleBack,
              ),
            ),
            body: OnboardingConfirmSection(
              exam: exam,
              examDate: _store.resolveExamDate(),
              experience: _store.experience,
              loading: _loading,
              onConfirm: _confirmEnroll,
            ),
          ),
        );
      },
    );
  }
}
