import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/firebase/analytics_service.dart';
import '../../../core/utils/responsive_helper.dart';
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

          if (ResponsiveHelper.isDesktop(context)) {
            return _buildDesktop(context, dashboard);
          }
          return _buildMobile(context, dashboard);
        },
      ),
    );
  }

  // ── Desktop layout ────────────────────────────────────────────────────────
  Widget _buildDesktop(BuildContext context, DashboardModel dashboard) {
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
              maxWidth: ResponsiveHelper.maxContentWidth),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 40, 32, 60),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─── Desktop header ─────────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_greeting()}, ${dashboard.user.firstName} 👋',
                            style: Theme.of(context)
                                .textTheme
                                .displaySmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            dashboard.user.selectedExamName ??
                                'Select your exam',
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: AppColors.primary.withOpacity(0.12),
                      child: Text(
                        dashboard.user.firstName[0].toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 22,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // ─── Stat cards row (always 3) ───────────────────────────
                Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                          child: StreakCard(
                              streak: dashboard.studyStreakDays)),
                      const SizedBox(width: 16),
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
                      const SizedBox(width: 16),
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
                const SizedBox(height: 20),

                // ─── Exam Countdown ─────────────────────────────────────
                if (dashboard.user.examDate != null) ...[
                  _ExamCountdownCard(user: dashboard.user, dashboard: dashboard),
                  const SizedBox(height: 20),
                ],


                // ─── Weekly Chart ───────────────────────────────────────
                  const SectionHeader(title: 'Weekly Activity 📈'),
                  const SizedBox(height: 12),
                  WeeklyChartCard(logs: dashboard.weeklyLogs),
                  const SizedBox(height: 28),

                // ─── Subject Progress — 2-column grid ───────────────────
                if (dashboard.subjectProgress.isNotEmpty) ...[
                  SectionHeader(
                    title: 'Subject Progress',
                    subtitle:
                        '${dashboard.completedTopics}/${dashboard.totalTopics} topics',
                  ),
                  const SizedBox(height: 16),
                  _SubjectGrid(
                      subjects: dashboard.subjectProgress,
                      columns: 2),
                ] else ...[
                  const _EmptySubjectCard(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Mobile / Tablet layout (existing, unchanged) ──────────────────────────
  Widget _buildMobile(BuildContext context, DashboardModel dashboard) {
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
                          user: dashboard.user,                          dashboard: dashboard,                        ),
                        const SizedBox(height: 16),
                      ],


                      // ─── Weekly Chart ──────────────────────────────────
                        const SectionHeader(title: 'Weekly Activity 📈'),
                        const SizedBox(height: 8),
                        WeeklyChartCard(logs: dashboard.weeklyLogs),
                        const SizedBox(height: 20),

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
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2-column subject grid (desktop)
// ─────────────────────────────────────────────────────────────────────────────

class _SubjectGrid extends StatelessWidget {
  final List<dynamic> subjects;
  final int columns;

  const _SubjectGrid({required this.subjects, required this.columns});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = 16.0;
        final itemWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: subjects
              .map((s) => SizedBox(
                    width: itemWidth,
                    child: SubjectProgressTile(progress: s),
                  ))
              .toList(),
        );
      },
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
// PREMIUM HERO EXAM COUNTDOWN CARD
// ─────────────────────────────────────────────────────────────────────────────
class _ExamCountdownCard extends StatefulWidget {
  final UserModel user;
  final DashboardModel dashboard;

  const _ExamCountdownCard({required this.user, required this.dashboard});

  @override
  State<_ExamCountdownCard> createState() => _ExamCountdownCardState();
}

class _ExamCountdownCardState extends State<_ExamCountdownCard>
    with TickerProviderStateMixin {
  late final AnimationController _glowCtrl;
  late final Animation<double> _glowAnim;
  late final AnimationController _floatCtrl;
  late final Animation<double> _floatAnim;
  late final AnimationController _entranceCtrl;
  late final Animation<double> _entranceFade;
  late final Animation<Offset> _entranceSlide;
  Timer? _msgTimer;
  int _msgIdx = 0;
  bool _tapped = false;

  static const _messages = [
    'One topic at a time, you\'ve got this 🚀',
    'Small daily progress wins the exam',
    'You are closer than yesterday 💪',
    'Every hour of study counts ⭐',
    'Believe in your preparation 🎯',
    'Your future is built daily 🌟',
    'Consistency beats intensity — keep going',
    'Stay focused, stay unstoppable 🔥',
  ];

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.28, end: 0.72).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut),
    );

    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    )..repeat(reverse: true);
    _floatAnim = CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut);

    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );
    _entranceFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOut),
    );
    _entranceSlide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOut));
    _entranceCtrl.forward();

    _msgIdx = math.Random().nextInt(_messages.length);
    _msgTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) setState(() => _msgIdx = (_msgIdx + 1) % _messages.length);
    });
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    _floatCtrl.dispose();
    _entranceCtrl.dispose();
    _msgTimer?.cancel();
    super.dispose();
  }

  String _fmtDate(String iso) {
    try {
      final isExplicit =
          iso.endsWith('Z') || RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(iso);
      final dt = DateTime.parse(isExplicit ? iso : '${iso}Z').toLocal();
      return DateFormat('d MMM yyyy').format(dt);
    } catch (_) {
      return iso;
    }
  }

  String _fmtH(double h) {
    final s = h.toStringAsFixed(1);
    return '${s.endsWith('.0') ? h.toInt() : s}h';
  }

  @override
  Widget build(BuildContext context) {
    final days = widget.user.daysUntilExam ?? 0;
    final isUrgent = days > 0 && days <= 30;
    final examName = widget.user.selectedExamName ?? 'Your Exam';
    final dailyTarget = widget.user.dailyTargetHours ?? 1.0;
    final todayHours = widget.dashboard.todayHours;
    final completionPct = widget.dashboard.overallCompletionPercent;
    final completedTopics = widget.dashboard.completedTopics;
    final totalTopics = widget.dashboard.totalTopics;
    final todayProgress =
        dailyTarget > 0 ? (todayHours / dailyTarget).clamp(0.0, 1.0) : 0.0;
    final isDesktop = ResponsiveHelper.isDesktop(context);

    final String statusLabel;
    final Color statusColor;
    if (days <= 0) {
      statusLabel = 'Exam Day! 🎉';
      statusColor = const Color(0xFF34D399);
    } else if (todayHours >= dailyTarget) {
      statusLabel = 'Ahead Today ✓';
      statusColor = const Color(0xFF34D399);
    } else if (isUrgent) {
      statusLabel = 'Need Focus 🔥';
      statusColor = const Color(0xFFFB7185);
    } else if (todayHours >= dailyTarget * 0.5) {
      statusLabel = 'On Track 👍';
      statusColor = const Color(0xFF34D399);
    } else {
      statusLabel = 'Behind Schedule';
      statusColor = const Color(0xFFFBBF24);
    }

    final List<Color> gradColors = isUrgent
        ? [const Color(0xFF3B0000), const Color(0xFF7F1D1D), const Color(0xFFB91C1C)]
        : [const Color(0xFF0D0421), const Color(0xFF2E1065), const Color(0xFF5B21B6)];

    return FadeTransition(
      opacity: _entranceFade,
      child: SlideTransition(
        position: _entranceSlide,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _tapped = true),
          onTapUp: (_) => setState(() => _tapped = false),
          onTapCancel: () => setState(() => _tapped = false),
          child: AnimatedScale(
            scale: _tapped ? 0.984 : 1.0,
            duration: const Duration(milliseconds: 100),
            child: AnimatedBuilder(
              animation: Listenable.merge([_glowAnim, _floatAnim]),
              builder: (context, child) => Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    stops: const [0.0, 0.5, 1.0],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: gradColors[2].withOpacity(_glowAnim.value * 0.55),
                      blurRadius: 40,
                      spreadRadius: 2,
                      offset: const Offset(0, 12),
                    ),
                    BoxShadow(
                      color: gradColors[1].withOpacity(0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Stack(
                    children: [
                      // Floating ambient orbs
                      _Orb(top: -20 + (_floatAnim as Animation<double>).value * 18, right: 50, size: 190, opacity: 0.07),
                      _Orb(bottom: -55 + _floatAnim.value * 14, right: -25, size: 230, opacity: 0.05),
                      _Orb(top: 35 - _floatAnim.value * 12, left: -45, size: 170, opacity: 0.055),
                      _Orb(top: 110 + _floatAnim.value * 10, right: 15, size: 95, opacity: 0.10),
                      _Orb(bottom: 20 - _floatAnim.value * 8, left: 80, size: 80, opacity: 0.06),
                      // Diagonal shine streak
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Transform.rotate(
                            angle: -math.pi / 8,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    Colors.white.withOpacity(0.025),
                                    Colors.transparent,
                                  ],
                                  stops: const [0.25, 0.5, 0.75],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      child!,
                    ],
                  ),
                ),
              ),
              child: Padding(
                padding: EdgeInsets.all(isDesktop ? 28.0 : 22.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // TOP: header row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: EdgeInsets.all(isDesktop ? 11 : 9),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white.withOpacity(0.22)),
                            boxShadow: [BoxShadow(color: Colors.white.withOpacity(0.06), blurRadius: 12, spreadRadius: 2)],
                          ),
                          child: Icon(Icons.school_rounded, color: Colors.white, size: isDesktop ? 22 : 19),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                examName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: isDesktop ? 18 : 16,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              if (widget.user.examDate != null) ...[
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Icon(Icons.event_rounded, color: Colors.white.withOpacity(0.55), size: 10),
                                    const SizedBox(width: 4),
                                    Text(
                                      _fmtDate(widget.user.examDate!),
                                      style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11, fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        _StatusPill(label: statusLabel, color: statusColor),
                      ],
                    ),

                    SizedBox(height: isDesktop ? 26 : 22),

                    // MIDDLE: countdown + ring
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                days <= 0 ? 'The day is here!' : 'DAYS LEFT',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.6),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.6,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  ShaderMask(
                                    shaderCallback: (bounds) => const LinearGradient(
                                      colors: [Colors.white, Color(0xFFDDD6FE)],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ).createShader(bounds),
                                    child: Text(
                                      days <= 0 ? '🎉' : '$days',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: isDesktop ? 84 : 70,
                                        fontWeight: FontWeight.w900,
                                        height: 0.92,
                                        shadows: [
                                          Shadow(color: Colors.white.withOpacity(0.45), blurRadius: 28),
                                          Shadow(color: const Color(0xFF8B5CF6).withOpacity(0.55), blurRadius: 56),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text('🚀', style: TextStyle(fontSize: isDesktop ? 28 : 22)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 700),
                                transitionBuilder: (child, anim) => FadeTransition(
                                  opacity: anim,
                                  child: SlideTransition(
                                    position: Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero)
                                        .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
                                    child: child,
                                  ),
                                ),
                                child: Row(
                                  key: ValueKey(_msgIdx),
                                  children: [
                                    Text('✨', style: TextStyle(fontSize: isDesktop ? 13 : 11)),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        _messages[_msgIdx],
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.75),
                                          fontSize: isDesktop ? 13 : 12,
                                          fontWeight: FontWeight.w500,
                                          fontStyle: FontStyle.italic,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: isDesktop ? 22 : 14),
                        _PremiumGoalRing(
                          progress: todayProgress,
                          todayHours: todayHours,
                          targetHours: dailyTarget,
                          isDesktop: isDesktop,
                        ),
                      ],
                    ),

                    SizedBox(height: isDesktop ? 22 : 18),

                    // Gradient divider
                    Container(
                      height: 1,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.white.withOpacity(0.22),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),

                    SizedBox(height: isDesktop ? 20 : 16),

                    // BOTTOM: stats row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Syllabus progress
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                const Text('📚', style: TextStyle(fontSize: 11)),
                                const SizedBox(width: 5),
                                Text('Syllabus', style: TextStyle(color: Colors.white.withOpacity(0.62), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                              ]),
                              const SizedBox(height: 6),
                              Text(
                                '${completionPct.toStringAsFixed(1)}%',
                                style: TextStyle(color: Colors.white, fontSize: isDesktop ? 22 : 20, fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 7),
                              TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0.0, end: (completionPct / 100).clamp(0.0, 1.0)),
                                duration: const Duration(milliseconds: 1400),
                                curve: Curves.easeOutCubic,
                                builder: (_, v, __) => Stack(
                                  children: [
                                    Container(height: 5, decoration: BoxDecoration(color: Colors.white.withOpacity(0.14), borderRadius: BorderRadius.circular(3))),
                                    FractionallySizedBox(
                                      widthFactor: v,
                                      child: Container(
                                        height: 5,
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(colors: [Color(0xFFA78BFA), Colors.white]),
                                          borderRadius: BorderRadius.circular(3),
                                          boxShadow: [BoxShadow(color: Colors.white.withOpacity(0.35), blurRadius: 6)],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text('$completedTopics of $totalTopics topics', style: TextStyle(color: Colors.white.withOpacity(0.52), fontSize: 10)),
                            ],
                          ),
                        ),
                        // Gradient vertical divider
                        Container(
                          width: 1,
                          height: 76,
                          margin: EdgeInsets.symmetric(horizontal: isDesktop ? 20 : 16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.transparent, Colors.white.withOpacity(0.2), Colors.transparent],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                        // Daily target
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                const Text('🎯', style: TextStyle(fontSize: 11)),
                                const SizedBox(width: 5),
                                Text('Daily Target', style: TextStyle(color: Colors.white.withOpacity(0.62), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                              ]),
                              const SizedBox(height: 6),
                              RichText(
                                text: TextSpan(children: [
                                  TextSpan(
                                    text: _fmtH(dailyTarget),
                                    style: TextStyle(color: Colors.white, fontSize: isDesktop ? 22 : 20, fontWeight: FontWeight.w800),
                                  ),
                                  TextSpan(
                                    text: ' /day',
                                    style: TextStyle(color: Colors.white.withOpacity(0.52), fontSize: 12, fontWeight: FontWeight.w500),
                                  ),
                                ]),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  color: todayHours >= dailyTarget
                                      ? const Color(0xFF059669).withOpacity(0.22)
                                      : Colors.white.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: todayHours >= dailyTarget
                                        ? const Color(0xFF34D399).withOpacity(0.4)
                                        : Colors.white.withOpacity(0.12),
                                  ),
                                ),
                                child: Text(
                                  todayHours >= dailyTarget ? 'Goal achieved! 🎉' : '${_fmtH(todayHours)} done today',
                                  style: TextStyle(
                                    color: todayHours >= dailyTarget ? const Color(0xFF34D399) : Colors.white.withOpacity(0.62),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Floating ambient orb ─────────────────────────────────────────────────────
class _Orb extends StatelessWidget {
  final double? top;
  final double? bottom;
  final double? left;
  final double? right;
  final double size;
  final double opacity;

  const _Orb({this.top, this.bottom, this.left, this.right, required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top, bottom: bottom, left: left, right: right,
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [Colors.white.withOpacity(opacity), Colors.transparent]),
        ),
      ),
    );
  }
}

// ─── Glowing status pill ──────────────────────────────────────────────────────
class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.13),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.5), width: 1.2),
        boxShadow: [BoxShadow(color: color.withOpacity(0.22), blurRadius: 10, spreadRadius: 1)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(
              color: color, shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color.withOpacity(0.9), blurRadius: 5, spreadRadius: 1)],
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.1)),
        ],
      ),
    );
  }
}

// ─── Premium circular goal ring ───────────────────────────────────────────────
class _PremiumGoalRing extends StatelessWidget {
  final double progress;
  final double todayHours;
  final double targetHours;
  final bool isDesktop;

  const _PremiumGoalRing(
      {required this.progress,
      required this.todayHours,
      required this.targetHours,
      required this.isDesktop});

  @override
  Widget build(BuildContext context) {
    final size = isDesktop ? 112.0 : 96.0;
    // Always teal/green like the reference — turns brighter when complete
    const ringColor = Color(0xFF34D399);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: progress),
      duration: const Duration(milliseconds: 1500),
      curve: Curves.easeOutCubic,
      builder: (_, value, __) => SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Ring painted with CustomPainter for the glowing dot
            CustomPaint(
              size: Size(size, size),
              painter: _RingPainter(progress: value, ringColor: ringColor),
            ),
            // Center text
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${(value * 100).round()}%',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isDesktop ? 20 : 17,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Daily Goal',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: isDesktop ? 10 : 9,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Ring CustomPainter — track + progress arc + glowing tip dot ─────────────
class _RingPainter extends CustomPainter {
  final double progress;
  final Color ringColor;

  const _RingPainter({required this.progress, required this.ringColor});

  static const double _stroke = 9.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - _stroke) / 2;
    const startAngle = -math.pi / 2; // 12 o'clock
    final sweepAngle = 2 * math.pi * progress.clamp(0.0, 1.0);

    // ── Background track ──────────────────────────────────────────────
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white.withOpacity(0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke,
    );

    if (progress < 0.005) return;

    // ── Progress arc ──────────────────────────────────────────────────
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..strokeCap = StrokeCap.round,
    );

    // ── Glowing dot at the arc tip ────────────────────────────────────
    final tipAngle = startAngle + sweepAngle;
    final tip = Offset(
      center.dx + radius * math.cos(tipAngle),
      center.dy + radius * math.sin(tipAngle),
    );

    // Outer soft glow layers
    for (int i = 4; i >= 1; i--) {
      canvas.drawCircle(
        tip,
        _stroke * 0.65 + i * 3.5,
        Paint()
          ..color = Colors.white.withOpacity(0.06 * (5 - i))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, i * 3.5),
      );
    }
    // Teal glow
    canvas.drawCircle(
      tip,
      _stroke * 0.9,
      Paint()
        ..color = ringColor.withOpacity(0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    // Bright white core
    canvas.drawCircle(
      tip,
      _stroke * 0.52,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.ringColor != ringColor;
}

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

