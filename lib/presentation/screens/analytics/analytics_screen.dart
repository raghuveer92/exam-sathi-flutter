import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/firebase/analytics_service.dart';
import '../../../core/utils/responsive_helper.dart';
import '../../../data/models/dashboard_model.dart';
import '../../blocs/dashboard/dashboard_bloc.dart';
import '../../widgets/dashboard/weekly_chart_card.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView(screenName: 'AnalyticsScreen');
    context.read<DashboardBloc>().add(DashboardLoadRequested());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: BlocBuilder<DashboardBloc, DashboardState>(
        builder: (context, state) {
          if (state is! DashboardLoaded) {
            return const Center(child: CircularProgressIndicator());
          }
          final d = state.dashboard;
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: ResponsiveHelper.isDesktop(context) ? 900 : double.infinity,
              ),
              child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Summary row
                Row(children: [
                  _AnalyticsSummaryCard(
                    label: 'Streak',
                    value: '${d.studyStreakDays}🔥',
                    color: AppColors.streakFire,
                  ),
                  const SizedBox(width: 12),
                  _AnalyticsSummaryCard(
                    label: 'Completed',
                    value: '${d.completedTopics}',
                    color: AppColors.success,
                  ),
                  const SizedBox(width: 12),
                  _AnalyticsSummaryCard(
                    label: 'Progress',
                    value: '${d.overallCompletionPercent.toStringAsFixed(0)}%',
                    color: AppColors.primary,
                  ),
                ]),
                const SizedBox(height: 20),
                if (d.weeklyLogs.isNotEmpty) ...[
                  Text('Weekly Hours',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  WeeklyChartCard(logs: d.weeklyLogs),
                ],
                const SizedBox(height: 20),
                Text('Subject Progress',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                ...d.subjectProgress.map((s) {
                  final color = s.color;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(s.icon, color: color, size: 18),
                                const SizedBox(width: 8),
                                Text(s.subjectName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                            Text(
                              '${s.completionPercent.toStringAsFixed(0)}%',
                              style: TextStyle(
                                  color: color, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: s.completionPercent / 100,
                            backgroundColor: color.withOpacity(0.12),
                            valueColor: AlwaysStoppedAnimation(color),
                            minHeight: 8,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AnalyticsSummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _AnalyticsSummaryCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
