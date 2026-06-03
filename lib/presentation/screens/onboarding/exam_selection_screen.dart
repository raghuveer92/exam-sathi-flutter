import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/firebase/analytics_service.dart';
import '../../../data/models/exam_subject_group_model.dart';
import '../../../data/models/exam_model.dart';
import '../../../data/repositories/dashboard_repository.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/dashboard/dashboard_bloc.dart';
import '../../widgets/common/optional_subject_selection_dialog.dart';

/// First screen after registration — student picks their target exam.
class ExamSelectionScreen extends StatefulWidget {
  final bool isChangeMode;

  const ExamSelectionScreen({
    super.key,
    this.isChangeMode = false,
  });

  @override
  State<ExamSelectionScreen> createState() => _ExamSelectionScreenState();
}

class _ExamSelectionScreenState extends State<ExamSelectionScreen> {
  List<ExamModel> _exams = [];
  bool _loading = true;
  int? _selected;

  @override
  void initState() {
    super.initState();
    _loadExams();
  }

  Future<void> _loadExams() async {
    try {
      final repo = GetIt.I<DashboardRepository>();
      final exams = await repo.getExams();
      setState(() {
        _exams = exams;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _confirm() async {
    if (_selected == null) return;
    try {
      final repo = GetIt.I<DashboardRepository>();
      final exam = _exams.firstWhere((e) => e.id == _selected);
      final groups = await repo.getExamSubjectGroups(exam.id);
      final selections = await _collectSelections(exam.name, groups);
      if (selections == null) return;

      final user = await repo.addMyExam(
        examId: exam.id,
        subjectSelections: selections,
      );
      if (mounted) {
        AnalyticsService.logExamSelected(examId: exam.id, examName: exam.name);
        final authState = context.read<AuthBloc>().state;
        if (authState is AuthAuthenticated) {
          final clearGoal = widget.isChangeMode;
          context.read<AuthBloc>().add(AuthUserUpdated(
                user: user,
              ));

          context.read<DashboardBloc>().add(
                DashboardExamChanged(
                  examId: exam.id,
                  examName: exam.name,
                  clearGoal: clearGoal,
                ),
              );

          if (widget.isChangeMode) {
            context.read<DashboardBloc>().add(DashboardResetRequested());
            context.go('/exam-goal', extra: exam);
          }
          // For onboarding flow, refreshListenable triggers navigation.
        } else {
          context.go('/exam-goal', extra: exam);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>?> _collectSelections(
    String examName,
    List<ExamSubjectGroupModel> groups,
  ) {
    return showOptionalSubjectSelectionDialog(
      context: context,
      examName: examName,
      groups: groups,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Text('Choose Your Exam 🎯',
                  style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 8),
              Text('Select the exam you are preparing for',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 32),
              if (_loading)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else
                Expanded(
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 1.2,
                    ),
                    itemCount: _exams.length,
                    itemBuilder: (context, i) {
                      final exam = _exams[i];
                      final isSelected = _selected == exam.id;
                      Color color;
                      try {
                        final hex = (exam.colorCode ?? '#6C63FF').replaceAll('#', '');
                        color = Color(int.parse('FF$hex', radix: 16));
                      } catch (_) {
                        color = AppColors.primary;
                      }
                      return GestureDetector(
                        onTap: () => setState(() => _selected = exam.id),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: isSelected ? color : color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected ? color : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.school_rounded,
                                  size: 36,
                                  color: isSelected ? Colors.white : color),
                              const SizedBox(height: 8),
                              Text(
                                exam.name,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: isSelected ? Colors.white : color,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _selected != null ? _confirm : null,
                  child: const Text('Continue'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
