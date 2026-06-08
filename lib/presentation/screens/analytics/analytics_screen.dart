import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/firebase/analytics_service.dart';
import '../../../core/utils/responsive_helper.dart';
import '../../../data/models/subject_progress_model.dart';
import '../../../data/models/user_exam_model.dart';
import '../../../data/repositories/dashboard_repository.dart';
import '../../blocs/dashboard/dashboard_bloc.dart';
import '../../widgets/analytics/analytics_exam_progress_section.dart';
import '../../widgets/analytics/analytics_weekly_chart.dart';
import '../mock_test/mock_test_performance_section.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final Map<int, List<SubjectProgressModel>> _subjectsByExam = {};
  bool _loadingSubjects = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView(screenName: 'AnalyticsScreen');
    final dashState = context.read<DashboardBloc>().state;
    if (dashState is! DashboardLoaded) {
      context.read<DashboardBloc>().add(DashboardLoadRequested());
    } else {
      unawaited(_loadSubjectsForAllExams(dashState.dashboard.myExams));
    }
  }

  Future<void> _refresh() async {
    context.read<DashboardBloc>().add(DashboardRefreshRequested());
  }

  Future<void> _loadSubjectsForAllExams(List<UserExamModel> exams) async {
    if (_loadingSubjects || !mounted) return;
    setState(() => _loadingSubjects = true);
    try {
      final repo = GetIt.I<DashboardRepository>();
      final grouped = <int, List<SubjectProgressModel>>{};
      for (final exam in exams) {
        final subjects =
            repo.getSubjectProgressCached(exam.examId) ?? const [];
        final sorted = List<SubjectProgressModel>.from(subjects)
          ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
        grouped[exam.examId] = sorted;
      }
      if (!mounted) return;
      setState(() {
        _subjectsByExam
          ..clear()
          ..addAll(grouped);
      });
    } finally {
      if (mounted) setState(() => _loadingSubjects = false);
    }
  }

  String _formatHours(double hours) {
    if (hours <= 0) return '0h';
    final totalMinutes = (hours * 60).round();
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  String _dailyTargetSubtitle(double todayHours, double dailyTarget) {
    if (dailyTarget <= 0) return 'Set a target date on your exams';
    final pct = (todayHours / dailyTarget * 100).round();
    return 'Today: ${_formatHours(todayHours)} / ${_formatHours(dailyTarget)} ($pct%)';
  }

  String? _activeExamName(List<UserExamModel> exams) {
    for (final exam in exams) {
      if (exam.isActive) return exam.examName;
    }
    if (exams.isNotEmpty) return exams.first.examName;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Analytics'),
        backgroundColor: AppColors.surface,
        elevation: 0,
      ),
      body: BlocConsumer<DashboardBloc, DashboardState>(
        listener: (context, state) {
          if (state is DashboardLoaded) {
            unawaited(_loadSubjectsForAllExams(state.dashboard.myExams));
          }
        },
        builder: (context, state) {
          if (state is! DashboardLoaded) {
            return const Center(child: CircularProgressIndicator());
          }

          final d = state.dashboard;
          final dailyTarget = state.calculatedDailyTarget;
          final activeExam = _activeExamName(d.myExams);
          final progressSubtitle = activeExam != null
              ? 'Across $activeExam'
              : 'Across Selected Exam';

          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth:
                    ResponsiveHelper.isDesktop(context) ? 900 : double.infinity,
              ),
              child: RefreshIndicator(
                onRefresh: _refresh,
                color: AppColors.primary,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _SummaryMetricCard(
                              title: 'Topics Completed',
                              value: '${d.completedTopics}',
                              subtitle: 'Completed Topics',
                              icon: Icons.check_circle_outline_rounded,
                              color: AppColors.success,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _SummaryMetricCard(
                              title: 'Overall Progress',
                              value:
                                  '${d.overallCompletionPercent.toStringAsFixed(0)}%',
                              subtitle: progressSubtitle,
                              icon: Icons.pie_chart_outline_rounded,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _SummaryMetricCard(
                              title: 'Daily Target',
                              value: dailyTarget > 0
                                  ? _formatHours(dailyTarget)
                                  : '--',
                              subtitle: _dailyTargetSubtitle(
                                d.todayHours,
                                dailyTarget,
                              ),
                              icon: Icons.track_changes_rounded,
                              color: AppColors.success,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      AnalyticsWeeklyChart(logs: d.weeklyLogs),
                      const SizedBox(height: 16),
                      const MockTestPerformanceSection(),
                      const SizedBox(height: 16),
                      if (_loadingSubjects && _subjectsByExam.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else
                        AnalyticsExamProgressSection(
                          exams: d.myExams,
                          subjectsByExam: _subjectsByExam,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SummaryMetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _SummaryMetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 132,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const Spacer(),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
