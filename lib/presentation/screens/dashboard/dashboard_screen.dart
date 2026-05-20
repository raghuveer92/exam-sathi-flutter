import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/firebase/analytics_service.dart';
import '../../../data/models/dashboard_model.dart';
import '../../../data/models/user_model.dart';
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
    AnalyticsService.logDashboardViewed();
    // Only load if not already loaded — prevents double-call from GoRouter
    // rebuilding the route tree on auth state changes (refreshListenable).
    final state = context.read<DashboardBloc>().state;
    if (state is DashboardInitial) {
      context.read<DashboardBloc>().add(DashboardLoadRequested());
    }
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

          final loaded = state as DashboardLoaded;
          final dashboard = loaded.dashboard;
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

                      // ─── Exam Countdown Card ───────────────────────────
                      if (dashboard.user.examDate != null) ...[
                        _ExamCountdownCard(
                          user: dashboard.user,
                          saveStatus: loaded.saveStatus,
                        ),
                        const SizedBox(height: 16),
                      ],

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

// ─────────────────────────────────────────────────────────────────────────────
// EXAM COUNTDOWN CARD  (with interactive daily-goal +/− buttons)
// ─────────────────────────────────────────────────────────────────────────────
class _ExamCountdownCard extends StatelessWidget {
  final UserModel user;
  final SaveStatus saveStatus;

  const _ExamCountdownCard({required this.user, required this.saveStatus});

  String _fmtDate(String iso) {
    try {
      return DateFormat('d MMM yyyy').format(DateTime.parse(iso));
    } catch (_) {
      return iso;
    }
  }

  String _fmtHours(double h) {
    final s = h.toStringAsFixed(1);
    return '${s.endsWith('.0') ? h.toInt() : s}h';
  }

  void _adjust(BuildContext context, double delta) {
    final current = user.dailyTargetHours ?? 1.0;
    final raw = (current + delta).clamp(0.5, 16.0);
    final snapped = (raw * 2).round() / 2.0; // snap to 0.5 steps
    context.read<DashboardBloc>().add(StudyHoursUpdated(snapped));
  }

  @override
  Widget build(BuildContext context) {
    final days = user.daysUntilExam ?? 0;
    final isUrgent = days <= 30;
    final examName = user.selectedExamName ?? 'Your Exam';
    final hours = user.dailyTargetHours ?? 1.0;

    final gradientColors = isUrgent
        ? const [Color(0xFFEF4444), Color(0xFFF97316)]
        : const [AppColors.primary, Color(0xFF8B5CF6)];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: gradientColors.first.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          // ── Left: exam name + days left ──────────────────────────────
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.school_rounded, color: Colors.white, size: 16),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        examName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  days <= 0 ? 'Exam day! 🎉' : '$days Days Left',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (user.syllabusTargetDate != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Syllabus by: ${_fmtDate(user.syllabusTargetDate!)}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── Right: interactive daily goal ────────────────────────────
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Daily Goal',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _HoursBtn(
                      icon: Icons.remove,
                      onTap: hours > 0.5 ? () => _adjust(context, -0.5) : null,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _fmtHours(hours),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _HoursBtn(
                      icon: Icons.add,
                      onTap: hours < 16.0 ? () => _adjust(context, 0.5) : null,
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                _SaveStatusChip(saveStatus: saveStatus),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Small circular +/− button ────────────────────────────────────────────────
class _HoursBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _HoursBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: onTap != null
              ? Colors.white.withOpacity(0.3)
              : Colors.white.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: onTap != null ? Colors.white : Colors.white38,
          size: 14,
        ),
      ),
    );
  }
}

// ─── Saving… / ✓ Saved indicator ─────────────────────────────────────────────
class _SaveStatusChip extends StatelessWidget {
  final SaveStatus saveStatus;

  const _SaveStatusChip({required this.saveStatus});

  @override
  Widget build(BuildContext context) {
    if (saveStatus == SaveStatus.saving) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 8,
            height: 8,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: Colors.white70,
            ),
          ),
          SizedBox(width: 4),
          Text('Saving…',
              style: TextStyle(color: Colors.white70, fontSize: 9)),
        ],
      );
    }
    if (saveStatus == SaveStatus.saved) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, color: Colors.white70, size: 10),
          SizedBox(width: 3),
          Text('Saved', style: TextStyle(color: Colors.white70, fontSize: 9)),
        ],
      );
    }
    // idle / pending — invisible placeholder so card height stays stable
    return const SizedBox(height: 10);
  }
}

