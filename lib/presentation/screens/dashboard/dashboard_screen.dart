import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/firebase/analytics_service.dart';
import '../../../data/models/dashboard_model.dart';
import '../../../data/models/subject_progress_model.dart';
import '../../../data/models/user_exam_model.dart';
import '../../../data/repositories/dashboard_repository.dart';
import '../../blocs/dashboard/dashboard_bloc.dart';
import '../../widgets/dashboard/overall_progress_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const Color _brandPrimary = Color(0xFF6C63FF);
  static const Color _brandSecondary = Color(0xFFFF8A00);

  final Map<int, List<SubjectProgressModel>> _subjectsByExam =
      <int, List<SubjectProgressModel>>{};
  bool _loadingSubjects = false;
  String _subjectsLoadKey = '';
  Completer<void>? _refreshCompleter;

  void _setStateSafely(VoidCallback updater) {
    if (!mounted) return;
    final phase = WidgetsBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(updater);
      });
      return;
    }
    setState(updater);
  }

  @override
  void initState() {
    super.initState();
    AnalyticsService.logDashboardViewed();
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

  Future<void> _refresh() async {
    final existingRefresh = _refreshCompleter;
    if (existingRefresh != null && !existingRefresh.isCompleted) {
      return existingRefresh.future;
    }

    final completer = Completer<void>();
    _refreshCompleter = completer;
    context.read<DashboardBloc>().add(DashboardRefreshRequested());
    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        _finishRefresh();
      },
    );
  }

  void _finishRefresh() {
    final completer = _refreshCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    _refreshCompleter = null;
  }

  Future<void> _activateExam(UserExamModel exam) async {
    try {
      final repo = GetIt.I<DashboardRepository>();
      await repo.setActiveMyExam(exam.id);
      if (!mounted) return;
      context.read<DashboardBloc>().add(DashboardLoadRequested());
      context.push('/subjects');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  void _ensureSubjectsLoaded(List<UserExamModel> exams) {
    final sortedIds = exams.map((e) => e.examId).toList()..sort();
    final loadKey = sortedIds.join('-');
    if (_loadingSubjects || loadKey.isEmpty || loadKey == _subjectsLoadKey) {
      return;
    }
    _subjectsLoadKey = loadKey;

    // Avoid triggering setState while the widget tree is currently building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _loadingSubjects) return;
      _setStateSafely(() => _loadingSubjects = true);
      unawaited(_loadSubjectsGroupedByExam(exams));
    });
  }

  Future<void> _loadSubjectsGroupedByExam(List<UserExamModel> exams) async {
    if (!mounted) return;
    try {
      final repo = GetIt.I<DashboardRepository>();
      final grouped = <int, List<SubjectProgressModel>>{};
      for (final exam in exams) {
        try {
          final subjects = await repo.getSubjectProgressByExam(exam.examId);
          subjects.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
          grouped[exam.examId] = subjects;
        } catch (_) {
          grouped[exam.examId] = const [];
        }
      }
      if (!mounted) return;
      _setStateSafely(() {
        _subjectsByExam
          ..clear()
          ..addAll(grouped);
      });
    } finally {
      if (mounted) _setStateSafely(() => _loadingSubjects = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: BlocConsumer<DashboardBloc, DashboardState>(
        listener: (context, state) {
          if (state is DashboardLoaded || state is DashboardError) {
            _finishRefresh();
          }
        },
        builder: (context, state) {
          if (state is DashboardInitial || state is DashboardLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is DashboardError) {
            return _ErrorState(
              message: state.message,
              onRetry: () =>
                  context.read<DashboardBloc>().add(DashboardLoadRequested()),
            );
          }

          final loaded = state as DashboardLoaded;
          final dashboard = loaded.dashboard;
          final exams = [...dashboard.myExams]..sort((a, b) {
              final ad = a.daysLeft ?? 1 << 20;
              final bd = b.daysLeft ?? 1 << 20;
              return ad.compareTo(bd);
            });

          _ensureSubjectsLoaded(exams);

          return RefreshIndicator(
            onRefresh: _refresh,
            color: _brandPrimary,
            triggerMode: RefreshIndicatorTriggerMode.anywhere,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isTwoColumn = constraints.maxWidth >= 960;
                final content = isTwoColumn
                    ? _buildTwoColumnDashboard(context, dashboard, exams)
                    : _buildSingleColumnDashboard(context, dashboard, exams);

                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1220),
                      child: content,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildSingleColumnDashboard(
    BuildContext context,
    DashboardModel dashboard,
    List<UserExamModel> exams,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeaderSection(
          greeting: _greeting(),
          firstName: dashboard.user.firstName,
        ),
        const SizedBox(height: 18),
        OverallProgressCard(dashboard: dashboard),
        const SizedBox(height: 18),
        _MyExamsSection(
          exams: exams,
          onActivate: _activateExam,
          onViewAll: () => context.push('/my-exams'),
          primary: _brandPrimary,
        ),
        const SizedBox(height: 18),
        _WeeklyAnalyticsCard(logs: dashboard.weeklyLogs),
        const SizedBox(height: 18),
        _SubjectsOverviewSection(
          exams: exams,
          subjectsByExam: _subjectsByExam,
          loading: _loadingSubjects,
          primary: _brandPrimary,
        ),
        const SizedBox(height: 14),
        _ManageExamsCard(
          onTap: () => context.push('/my-exams'),
          primary: _brandPrimary,
        ),
      ],
    );
  }

  Widget _buildTwoColumnDashboard(
    BuildContext context,
    DashboardModel dashboard,
    List<UserExamModel> exams,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeaderSection(
          greeting: _greeting(),
          firstName: dashboard.user.firstName,
        ),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                children: [
                  OverallProgressCard(dashboard: dashboard),
                  const SizedBox(height: 18),
                  _MyExamsSection(
                    exams: exams,
                    onActivate: _activateExam,
                    onViewAll: () => context.push('/my-exams'),
                    primary: _brandPrimary,
                  ),
                  const SizedBox(height: 18),
                  _ManageExamsCard(
                    onTap: () => context.push('/my-exams'),
                    primary: _brandPrimary,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                children: [
                  _WeeklyAnalyticsCard(logs: dashboard.weeklyLogs),
                  const SizedBox(height: 18),
                  _SubjectsOverviewSection(
                    exams: exams,
                    subjectsByExam: _subjectsByExam,
                    loading: _loadingSubjects,
                    primary: _brandPrimary,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HeaderSection extends StatelessWidget {
  final String greeting;
  final String firstName;

  const _HeaderSection({required this.greeting, required this.firstName});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ExamSaathi',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppColors.textSecondary,
                      letterSpacing: 0.3,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                '$greeting, $firstName 👋',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
              ),
            ],
          ),
        ),
        CircleAvatar(
          radius: 22,
          backgroundColor: const Color(0x116C63FF),
          child: Text(
            firstName.isEmpty ? 'S' : firstName[0].toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF6C63FF),
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
        ),
      ],
    );
  }
}

// --- Premium Dashboard Card ---
class PremiumDashboardCard extends StatelessWidget {
  final UserExamModel? exam;
  final double todayHours;
  final double goalHours;
  final double overallPercent;
  final int topicsDone;
  final int topicsTotal;
  final int? daysLeft;
  final int streak;

  const PremiumDashboardCard({
    super.key,
    required this.exam,
    required this.todayHours,
    required this.goalHours,
    required this.overallPercent,
    required this.topicsDone,
    required this.topicsTotal,
    required this.daysLeft,
    required this.streak,
  });

  @override
  Widget build(BuildContext context) {
    final Color examColor = const Color(0xFF6C63FF); // fallback brand color
    final String examName = exam?.examName ?? 'Your Exam';
    final int dLeft = daysLeft ?? 0;
    final double ratio = goalHours <= 0 ? 0.0 : (todayHours / goalHours).clamp(0.0, 1.0);
    final int percent = (ratio * 100).round();
    final String progressText = '${todayHours.toStringAsFixed(1)}h / ${goalHours.toStringAsFixed(goalHours.truncateToDouble() == goalHours ? 0 : 1)}h';
    final bool syllabusComplete = overallPercent >= 99.5;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [examColor, examColor.withOpacity(0.7), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: examColor.withOpacity(0.18),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Exam icon and name
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.white,
                child: Icon(
                  Icons.emoji_events_rounded,
                  color: examColor,
                  size: 32,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      examName,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            fontSize: 22,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.calendar_today_rounded, color: Colors.white70, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          dLeft > 0 ? '$dLeft days left' : 'Exam soon!',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.white70,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.local_fire_department, color: Colors.orange, size: 16),
                              const SizedBox(width: 3),
                              Text('$streak day streak', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Motivation badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amberAccent.shade100.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.amber.withOpacity(0.18),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: const [
                    Icon(Icons.emoji_events_rounded, color: Colors.deepOrange, size: 18),
                    SizedBox(width: 5),
                    Text('Premium', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.deepOrange, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Progress ring
              SizedBox(
                width: 90,
                height: 90,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: ratio,
                      strokeWidth: 10,
                      color: Colors.white,
                      backgroundColor: Colors.white24,
                    ),
                    Text(
                      '$percent%',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              // Daily goal
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Today's Goal",
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      progressText,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Syllabus progress
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Syllabus Progress',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$topicsDone of $topicsTotal topics',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 120,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: overallPercent / 100,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                    minHeight: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Motivation message
          Text(
            syllabusComplete
                ? '🎉 Syllabus Complete! You’re ready for the exam.'
                : (percent >= 70
                    ? 'Great progress! Keep it up 🔥'
                    : 'Small steps daily make big results ✨'),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _MyExamsSection extends StatelessWidget {
  final List<UserExamModel> exams;
  final ValueChanged<UserExamModel> onActivate;
  final VoidCallback onViewAll;
  final Color primary;

  const _MyExamsSection({
    required this.exams,
    required this.onActivate,
    required this.onViewAll,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    if (exams.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'My Exams',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const Spacer(),
            TextButton(
              onPressed: onViewAll,
              child: const Text(
                'View All',
                style: TextStyle(
                  color: Color(0xFF6C63FF),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 208,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: exams.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final exam = exams[index];
              final isNearest = index == 0;
              return _ExamCard(
                exam: exam,
                isNearest: isNearest,
                onTap: () => onActivate(exam),
                primary: primary,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ExamCard extends StatelessWidget {
  final UserExamModel exam;
  final bool isNearest;
  final VoidCallback onTap;
  final Color primary;

  const _ExamCard({
    required this.exam,
    required this.isNearest,
    required this.onTap,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    final progress = ((exam.progressPercent ?? 0.0) / 100).clamp(0.0, 1.0);
    final width = isNearest ? 190.0 : 172.0;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: width,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isNearest ? const Color(0xFFFF8A00) : const Color(0xFFEAEAF1),
            width: isNearest ? 1.6 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isNearest)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0E2),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Nearest',
                  style: TextStyle(
                    color: Color(0xFFFF8A00),
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
            if (isNearest) const SizedBox(height: 8),
            Text(
              exam.examName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              exam.examDate ?? 'Date pending',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 10),
            Text(
              '${exam.daysLeft ?? 0}',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            Text(
              'Days Left',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const Spacer(),
            Text(
              '${(exam.progressPercent ?? 0).toStringAsFixed(0)}%',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: primary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 6,
                value: progress,
                color: primary,
                backgroundColor: const Color(0xFFEDEEF7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeeklyAnalyticsCard extends StatelessWidget {
  final List<DailyLogModel> logs;

  const _WeeklyAnalyticsCard({required this.logs});

  @override
  Widget build(BuildContext context) {
    final weekHours = List<double>.filled(7, 0);

    for (final log in logs) {
      try {
        final date = DateTime.parse(log.studyDate);
        final weekday = date.weekday; // Mon=1...Sun=7
        weekHours[weekday - 1] += log.hoursStudied;
      } catch (_) {}
    }

    final total = weekHours.fold<double>(0.0, (sum, h) => sum + h);
    final avg = total / 7;
    final maxHours = weekHours.fold<double>(0.0, math.max);
    final top = maxHours <= 0 ? 1.0 : maxHours;
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "This Week's Study",
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 160,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (index) {
                final h = weekHours[index];
                final height = (h / top) * 96;
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        '${h.toStringAsFixed(1)}h',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 6),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: 16,
                        height: height < 6 ? 6 : height,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFA143), Color(0xFFFF8A00)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        labels[index],
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FE),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _SummaryMetric(
                    icon: Icons.schedule_rounded,
                    label: 'Total Study Time',
                    value: '${total.toStringAsFixed(1)}h',
                    color: const Color(0xFFFF8A00),
                  ),
                ),
                Container(width: 1, height: 38, color: const Color(0xFFE5E7F0)),
                Expanded(
                  child: _SummaryMetric(
                    icon: Icons.track_changes_rounded,
                    label: 'Daily Average',
                    value: '${avg.toStringAsFixed(1)}h',
                    color: const Color(0xFF6C63FF),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _SummaryMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SubjectsOverviewSection extends StatefulWidget {
  final List<UserExamModel> exams;
  final Map<int, List<SubjectProgressModel>> subjectsByExam;
  final bool loading;
  final Color primary;

  const _SubjectsOverviewSection({
    required this.exams,
    required this.subjectsByExam,
    required this.loading,
    required this.primary,
  });

  @override
  State<_SubjectsOverviewSection> createState() =>
      _SubjectsOverviewSectionState();
}

class _SubjectsOverviewSectionState extends State<_SubjectsOverviewSection> {
  late final Set<int> _expandedExamIds;

  @override
  void initState() {
    super.initState();
    _expandedExamIds = widget.exams.map((e) => e.examId).toSet();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Subjects Overview',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          if (widget.loading && widget.subjectsByExam.isEmpty)
            const Center(child: CircularProgressIndicator())
          else
            ...widget.exams.map((exam) {
              final subjects = widget.subjectsByExam[exam.examId] ??
                  const <SubjectProgressModel>[];
              final isExpanded = _expandedExamIds.contains(exam.examId);
              final examProgress = exam.progressPercent ?? 0;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FE),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE7E8F2)),
                ),
                child: Column(
                  children: [
                    ListTile(
                      title: Text(
                        exam.examName,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${examProgress.toStringAsFixed(0)}% Complete',
                            style: TextStyle(
                              color: widget.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            isExpanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                          ),
                        ],
                      ),
                      onTap: () {
                        setState(() {
                          if (isExpanded) {
                            _expandedExamIds.remove(exam.examId);
                          } else {
                            _expandedExamIds.add(exam.examId);
                          }
                        });
                      },
                    ),
                    if (isExpanded)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: subjects.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  'No subject progress yet.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: AppColors.textSecondary),
                                ),
                              )
                            : Column(
                                children: subjects
                                    .map((subject) => _SubjectRow(
                                          exam: exam,
                                          subject: subject,
                                        ))
                                    .toList(),
                              ),
                      ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8EE),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Progress is calculated based on topics completed in each exam.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF7A7F8F),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubjectRow extends StatelessWidget {
  final UserExamModel exam;
  final SubjectProgressModel subject;

  const _SubjectRow({required this.exam, required this.subject});

  @override
  Widget build(BuildContext context) {
    final progress = (subject.completionPercent / 100).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final repo = GetIt.I<DashboardRepository>();
          if (!exam.isActive) {
            await repo.setActiveMyExam(exam.id);
          }
          if (!context.mounted) return;
          context.go('/subjects/${subject.subjectId}');
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      subject.subjectName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    '${subject.completionPercent.toStringAsFixed(0)}%',
                    style: const TextStyle(
                      color: Color(0xFF6C63FF),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${subject.completedTopics}/${subject.totalTopics} topics',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textHint,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  value: progress,
                  color: const Color(0xFF6C63FF),
                  backgroundColor: const Color(0xFFEDEEF7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManageExamsCard extends StatelessWidget {
  final VoidCallback onTap;
  final Color primary;

  const _ManageExamsCard({required this.onTap, required this.primary});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE8E9F2)),
        ),
        child: Row(
          children: [
            Icon(Icons.edit_note_rounded, color: primary),
            const SizedBox(width: 10),
            Text(
              'Manage Exams',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const Spacer(),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_rounded,
                size: 54, color: AppColors.textHint),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
