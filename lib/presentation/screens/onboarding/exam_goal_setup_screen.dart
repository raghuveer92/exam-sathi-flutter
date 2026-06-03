import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/exam_model.dart';
import '../../../data/repositories/dashboard_repository.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/dashboard/dashboard_bloc.dart';

/// Screen shown after exam selection — allows student to set their exam date
/// and creates a personalised study timeline.
class ExamGoalSetupScreen extends StatefulWidget {
  final ExamModel? exam;

  const ExamGoalSetupScreen({super.key, this.exam});

  @override
  State<ExamGoalSetupScreen> createState() => _ExamGoalSetupScreenState();
}

class _ExamGoalSetupScreenState extends State<ExamGoalSetupScreen> {
  DateTime? _examDate;
  DateTime? _syllabusDate;
  bool _loadingHours = true;
  bool _submitting = false;
  double? _totalHours;
  ExamModel? _fetchedExam; // used when widget.exam is null (router redirect)

  ExamModel? get _exam => widget.exam ?? _fetchedExam;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final repo = GetIt.I<DashboardRepository>();
      // Parallel: dashboard (for total hours) + exams list (for subjectCount when exam not passed)
      final futures = await Future.wait([
        repo.getDashboard(),
        if (widget.exam == null) repo.getExams(),
      ]);
      if (!mounted) return;
      final dashboard = futures[0] as dynamic;
      setState(() {
        _totalHours = dashboard.totalEstimatedHours > 0 ? dashboard.totalEstimatedHours : null;
        _loadingHours = false;
      });
      if (widget.exam == null && futures.length > 1) {
        final exams = futures[1] as List<ExamModel>;
        final authState = context.read<AuthBloc>().state;
        final selectedId = authState is AuthAuthenticated ? authState.user.selectedExamId : null;
        if (selectedId != null && mounted) {
          final match = exams.cast<ExamModel?>().firstWhere(
            (e) => e?.id == selectedId,
            orElse: () => exams.isNotEmpty ? exams.first : null,
          );
          setState(() => _fetchedExam = match);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loadingHours = false);
    }
  }

  int get _daysRemaining {
    if (_examDate == null) return 0;
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final examStart = DateTime(_examDate!.year, _examDate!.month, _examDate!.day);
    return examStart.difference(todayStart).inDays;
  }

  double get _dailyTarget {
    if (_totalHours == null || _daysRemaining <= 0) return 0;
    return _totalHours! / _daysRemaining;
  }

  double get _weeklyTarget => _dailyTarget * 7;

  Future<void> _pickExamDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _examDate ?? DateTime.now().add(const Duration(days: 90)),
      firstDate: DateTime.now().add(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 1500)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      final minSyllabusDate = DateTime.now().add(const Duration(days: 1));
      final latestSyllabusDate = picked.subtract(const Duration(days: 1));
      DateTime? nextSyllabusDate;

      if (!minSyllabusDate.isAfter(latestSyllabusDate)) {
        final suggested = picked.subtract(const Duration(days: 30));
        nextSyllabusDate = suggested.isBefore(minSyllabusDate) ? minSyllabusDate : suggested;
      } else {
        // If exam is too close, there is no valid syllabus date before exam.
        nextSyllabusDate = null;
      }

      setState(() {
        _examDate = picked;
        _syllabusDate = nextSyllabusDate;
      });
    }
  }

  Future<void> _pickSyllabusDate() async {
    if (_examDate == null) return;
    final minDate = DateTime.now().add(const Duration(days: 1));
    final maxDate = _examDate!.subtract(const Duration(days: 1));
    if (minDate.isAfter(maxDate)) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: (_syllabusDate != null && _syllabusDate!.isBefore(maxDate))
          ? _syllabusDate!
          : maxDate,
      firstDate: minDate,
      lastDate: maxDate,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.secondary),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) setState(() => _syllabusDate = picked);
  }

  Future<void> _continue() async {
    if (_examDate == null) return;
    setState(() => _submitting = true);
    try {
      final repo = GetIt.I<DashboardRepository>();
      await repo.setExamGoal(
        examDate: _examDate!,
        syllabusTargetDate: _syllabusDate,
      );
      if (mounted) {
        final authState = context.read<AuthBloc>().state;
        if (authState is AuthAuthenticated) {
          context.read<AuthBloc>().add(AuthUserUpdated(
                user: authState.user.copyWith(
                  examDate: '${_examDate!.year.toString().padLeft(4, '0')}-'
                      '${_examDate!.month.toString().padLeft(2, '0')}-'
                      '${_examDate!.day.toString().padLeft(2, '0')}',
                ),
              ));
          context.read<DashboardBloc>().add(DashboardResetRequested());
          context.read<DashboardBloc>().add(DashboardLoadRequested());
          context.go('/home');
        } else {
          context.go('/home');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  String _fmtDate(DateTime d) => DateFormat('d MMM yyyy').format(d);

  String _fmtHDay(double h) {
    if (h <= 0) return '—';
    if (h < 1) return '${(h * 60).round()}m/day';
    final s = h.toStringAsFixed(1);
    return s.endsWith('.0') ? '${h.toInt()}h/day' : '${s}h/day';
  }

  String _fmtHWeek(double h) {
    if (h <= 0) return '—';
    final s = h.toStringAsFixed(1);
    return s.endsWith('.0') ? '${h.toInt()}h/wk' : '${s}h/wk';
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    final user = authState is AuthAuthenticated ? authState.user : null;
    final examName = _exam?.name ?? user?.selectedExamName ?? 'Your Exam';
    final subjectCount = _exam?.subjectCount;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          color: AppColors.textPrimary,
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/my-exams?onboarding=1'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ─────────────────────────────────────────────────────
            Text(
              'Set Your Exam Goal',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose your exam date to create your preparation timeline.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 28),

            // ── Selected Exam Card ──────────────────────────────────────────
            _ExamCard(
              name: examName,
              subjectCount: subjectCount,
              totalHours: _totalHours,
              loading: _loadingHours,
            ),
            const SizedBox(height: 28),

            // ── Exam Date ──────────────────────────────────────────────────
            _SectionLabel('Select Your Exam Date *'),
            const SizedBox(height: 10),
            _DateTile(
              date: _examDate,
              hint: 'Tap to select exam date',
              icon: Icons.event_rounded,
              color: AppColors.primary,
              onTap: _pickExamDate,
            ),
            const SizedBox(height: 24),

            // ── Syllabus Completion Date ────────────────────────────────────
            _SectionLabel('Target Syllabus Completion Date'),
            const SizedBox(height: 4),
            Text(
              'Recommended to complete syllabus before exam for revision.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 10),
            _DateTile(
              date: _syllabusDate,
              hint: _examDate == null
                  ? 'Select exam date first'
                  : 'Auto-suggested: 30 days before exam',
              icon: Icons.menu_book_rounded,
              color: AppColors.secondary,
              onTap: _examDate != null ? _pickSyllabusDate : null,
              enabled: _examDate != null,
            ),
            const SizedBox(height: 28),

            // ── Timeline Preview ────────────────────────────────────────────
            if (_examDate != null) ...[
              _TimelineCard(
                daysRemaining: _daysRemaining,
                totalHours: _totalHours,
                dailyTarget: _dailyTarget,
                weeklyTarget: _weeklyTarget,
                syllabusDate: _syllabusDate,
                fmtHDay: _fmtHDay,
                fmtHWeek: _fmtHWeek,
                fmtDate: _fmtDate,
              ),
              const SizedBox(height: 28),
            ],

            // ── CTA ──────────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _examDate != null && !_submitting ? _continue : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor: AppColors.primary.withOpacity(0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Text(
                        'Continue  →',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EXAM CARD
// ─────────────────────────────────────────────────────────────────────────────
class _ExamCard extends StatelessWidget {
  final String name;
  final int? subjectCount;
  final double? totalHours;
  final bool loading;

  const _ExamCard({
    required this.name,
    required this.subjectCount,
    required this.totalHours,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if (subjectCount != null && subjectCount! > 0) {
      parts.add('$subjectCount Subject${subjectCount! > 1 ? 's' : ''}');
    }
    if (totalHours != null && totalHours! > 0) {
      parts.add('${totalHours!.toStringAsFixed(0)} Study Hours');
    }
    final subtitle = parts.join(' • ');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.school_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                if (loading)
                  Container(
                    width: 130,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  )
                else
                  Text(
                    subtitle.isNotEmpty ? subtitle : 'No syllabus added yet',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 13,
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

// ─────────────────────────────────────────────────────────────────────────────
// SECTION LABEL
// ─────────────────────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// DATE TILE
// ─────────────────────────────────────────────────────────────────────────────
class _DateTile extends StatelessWidget {
  final DateTime? date;
  final String hint;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool enabled;

  const _DateTile({
    required this.date,
    required this.hint,
    required this.icon,
    required this.color,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final hasDate = date != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: hasDate ? color.withOpacity(0.07) : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasDate
                ? color
                : enabled
                    ? AppColors.divider
                    : AppColors.divider.withOpacity(0.5),
            width: hasDate ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: hasDate
                    ? color.withOpacity(0.12)
                    : AppColors.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: hasDate
                    ? color
                    : enabled
                        ? AppColors.textSecondary
                        : AppColors.textHint,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                hasDate
                    ? DateFormat('EEEE, d MMM yyyy').format(date!)
                    : hint,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: hasDate ? FontWeight.w600 : FontWeight.w400,
                  color: hasDate
                      ? color
                      : enabled
                          ? AppColors.textSecondary
                          : AppColors.textHint,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: enabled ? AppColors.textSecondary : AppColors.textHint,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TIMELINE CARD
// ─────────────────────────────────────────────────────────────────────────────
class _TimelineCard extends StatelessWidget {
  final int daysRemaining;
  final double? totalHours;
  final double dailyTarget;
  final double weeklyTarget;
  final DateTime? syllabusDate;
  final String Function(double) fmtHDay;
  final String Function(double) fmtHWeek;
  final String Function(DateTime) fmtDate;

  const _TimelineCard({
    required this.daysRemaining,
    required this.totalHours,
    required this.dailyTarget,
    required this.weeklyTarget,
    required this.syllabusDate,
    required this.fmtHDay,
    required this.fmtHWeek,
    required this.fmtDate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.timeline_rounded,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                'Your Preparation Timeline',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _TimelineStat(
                  icon: Icons.calendar_today_rounded,
                  iconColor: AppColors.primary,
                  label: 'Days Left',
                  value: '$daysRemaining',
                ),
              ),
              if (totalHours != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: _TimelineStat(
                    icon: Icons.menu_book_rounded,
                    iconColor: AppColors.secondary,
                    label: 'Syllabus',
                    value: '${totalHours!.toStringAsFixed(0)}h',
                  ),
                ),
              ],
              if (dailyTarget > 0) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: _TimelineStat(
                    icon: Icons.bolt_rounded,
                    iconColor: AppColors.warning,
                    label: 'Daily',
                    value: fmtHDay(dailyTarget),
                  ),
                ),
              ],
              if (weeklyTarget > 0) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: _TimelineStat(
                    icon: Icons.repeat_rounded,
                    iconColor: AppColors.success,
                    label: 'Weekly',
                    value: fmtHWeek(weeklyTarget),
                  ),
                ),
              ],
            ],
          ),
          if (syllabusDate != null) ...[
            const SizedBox(height: 16),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.secondary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.flag_rounded,
                      color: AppColors.secondary, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Complete syllabus by: ${fmtDate(syllabusDate!)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.secondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TimelineStat extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _TimelineStat({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 16),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: iconColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
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
