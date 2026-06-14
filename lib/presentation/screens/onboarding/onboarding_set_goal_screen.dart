import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/onboarding/onboarding_wizard_store.dart';
import '../../../core/router/app_navigation.dart';
import '../../../core/testing/test_keys.dart';
import '../../../data/repositories/dashboard_repository.dart';
import '../../blocs/auth/auth_bloc.dart';
import 'onboarding_choose_exam_screen.dart';
import 'widgets/onboarding_shared_widgets.dart';

/// Screen 2 — set goal (onboarding).
class OnboardingSetGoalScreen extends StatefulWidget {
  const OnboardingSetGoalScreen({super.key});

  @override
  State<OnboardingSetGoalScreen> createState() =>
      _OnboardingSetGoalScreenState();
}

class _OnboardingSetGoalScreenState extends State<OnboardingSetGoalScreen> {
  late final OnboardingWizardStore _store;
  bool _resolvingSubjects = false;

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
      return;
    }

    if (_store.selectionInProgress) {
      _resolvingSubjects = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _finishExamSelection());
    }
  }

  Future<void> _finishExamSelection() async {
    await completeOnboardingExamSelection(
      context: context,
      store: _store,
      dashboardRepo: GetIt.I<DashboardRepository>(),
    );
    if (mounted) {
      setState(() => _resolvingSubjects = false);
    }
  }

  void _handleBack() {
    if (_store.selectionInProgress) return;
    _store.cancelExamSelection();
    AppNavigation.popOrGoIfDifferent(context, '/onboarding/choose-exam');
  }

  void _continueToConfirm() {
    AppNavigation.pushIfDifferent(context, '/onboarding/confirm');
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
              title: const Text('Set Your Goal'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _store.selectionInProgress ? null : _handleBack,
              ),
            ),
            body: Stack(
              children: [
                OnboardingGoalForm(
                  datePreset: _store.datePreset,
                  examDate: _store.customExamDate,
                  experience: _store.experience,
                  onDatePreset: (v) => _store.updateGoal(datePreset: v),
                  onCustomDate: (d) =>
                      _store.updateGoal(datePreset: 'custom', customExamDate: d),
                  onExperience: (e) => _store.updateGoal(experience: e),
                  onContinue: _continueToConfirm,
                ),
                if (_resolvingSubjects || _store.selectionInProgress)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.white.withValues(alpha: 0.65),
                      child: const Center(
                        key: TestKeys.examSelectionInProgress,
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
