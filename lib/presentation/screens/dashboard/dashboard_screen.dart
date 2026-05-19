import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../data/models/dashboard_model.dart';
import '../../blocs/dashboard/dashboard_bloc.dart';
import '../../widgets/dashboard/streak_card.dart';
import '../../widgets/dashboard/overall_progress_card.dart';
import '../../widgets/dashboard/subject_progress_tile.dart';
import '../../widgets/dashboard/weekly_chart_card.dart';
import '../../widgets/dashboard/stat_card.dart';
import '../../widgets/common/section_header.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    context.read<DashboardBloc>().add(DashboardLoadRequested());
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  Future<void> _onRefresh() async {
    context.read<DashboardBloc>().add(DashboardRefreshRequested());
    await Future.delayed(const Duration(milliseconds: 800));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: BlocBuilder<DashboardBloc, DashboardState>(
        builder: (context, state) {
          if (state is DashboardLoading || state is DashboardInitial) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is DashboardError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.wifi_off_rounded,
                      size: 64, color: AppColors.textHint),
                  const SizedBox(height: 16),
                  Text(state.message,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () =>
                        context.read<DashboardBloc>().add(DashboardLoadRequested()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final dashboard = (state as DashboardLoaded).dashboard;
          return RefreshIndicator(
            onRefresh: _onRefresh,
            color: AppColors.primary,
            child: CustomScrollView(
              slivers: [
                // ─── App Bar ─────────────────────────────────────────────
                SliverAppBar(
                  backgroundColor: AppColors.background,
                  floating: true,
                  snap: true,
                  elevation: 0,
                  toolbarHeight: 70,
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_greeting()}, ${dashboard.user.firstName} 👋',
                        style:
                            Theme.of(context).textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                      Text(
                        dashboard.user.selectedExamName ?? 'Select your exam',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: CircleAvatar(
                        radius: 22,
                        backgroundColor: AppColors.primary.withOpacity(0.15),
                        child: Text(
                          dashboard.user.firstName[0].toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // ─── Row: Streak + Stats ────────────────────────────
                      Row(
                        children: [
                          Expanded(
                            child: StreakCard(
                              streak: dashboard.studyStreakDays,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: StatCard(
                              icon: Icons.timer_rounded,
                              iconColor: AppColors.secondary,
                              label: 'Today',
                              value:
                                  '${dashboard.todayHours.toStringAsFixed(1)}h',
                              subtitle: 'Hours studied',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: StatCard(
                              icon: Icons.check_circle_rounded,
                              iconColor: AppColors.success,
                              label: 'Done',
                              value: '${dashboard.todayTopicsCompleted}',
                              subtitle: 'Topics today',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ─── Overall Progress Card ─────────────────────────
                      OverallProgressCard(dashboard: dashboard),
                      const SizedBox(height: 20),

                      // ─── Weekly Chart ──────────────────────────────────
                      if (dashboard.weeklyLogs.isNotEmpty) ...[
                        const SectionHeader(title: 'Weekly Activity 📈'),
                        const SizedBox(height: 8),
                        WeeklyChartCard(logs: dashboard.weeklyLogs),
                        const SizedBox(height: 20),
                      ],

                      // ─── Subject Progress ──────────────────────────────
                      if (dashboard.subjectProgress.isNotEmpty) ...[
                        SectionHeader(
                          title: 'Subject Progress',
                          subtitle:
                              '${dashboard.completedTopics}/${dashboard.totalTopics} topics',
                        ),
                        const SizedBox(height: 12),
                        ...dashboard.subjectProgress
                            .map((s) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: SubjectProgressTile(progress: s),
                                ))
                            .toList(),
                      ] else ...[
                        const _EmptySubjectCard(),
                      ],
                    ]),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _EmptySubjectCard extends StatelessWidget {
  const _EmptySubjectCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Icon(Icons.school_outlined, size: 48, color: AppColors.textHint),
          const SizedBox(height: 12),
          Text('No syllabus yet',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Your subjects will appear here once the admin adds syllabus.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
