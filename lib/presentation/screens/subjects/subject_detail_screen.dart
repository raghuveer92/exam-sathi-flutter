import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/firebase/analytics_service.dart';
import '../../../core/utils/responsive_helper.dart';
import '../../../data/models/subject_detail_model.dart';
import '../../../data/models/topic_model.dart';
import '../../../data/repositories/progress_repository.dart';
import '../../blocs/dashboard/dashboard_bloc.dart';

// ─── Topic status helper ────────────────────────────────────────────────────
enum _TopicStatus { notStarted, inProgress, completed }

_TopicStatus _statusOf(TopicModel t) {
  if (t.isCompleted || t.status == 'COMPLETED') return _TopicStatus.completed;
  if (t.actualHours > 0 || t.status == 'IN_PROGRESS') return _TopicStatus.inProgress;
  return _TopicStatus.notStarted;
}

String _fmtH(double h) {
  final s = h.toStringAsFixed(1);
  return s.endsWith('.0') ? '${h.toInt()}h' : '${s}h';
}

/// Returns today's date as YYYY-MM-DD in the LOCAL timezone.
/// Using year/month/day directly avoids toIso8601String() returning UTC on web.
String _localTodayDate() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}

/// Parses a backend timestamp to local DateTime.
/// Spring Boot LocalDateTime serialises as "2026-05-22T17:00:00.000" — no Z,
/// but the value is UTC.  Append Z so Dart treats it as UTC before converting.
DateTime _parseBackendTimestamp(String s) {
  final isExplicit = s.endsWith('Z') || RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(s);
  return DateTime.parse(isExplicit ? s : '${s}Z').toLocal();
}

// ─── Screen ────────────────────────────────────────────────────────────────
class SubjectDetailScreen extends StatefulWidget {
  final int subjectId;
  const SubjectDetailScreen({super.key, required this.subjectId});

  @override
  State<SubjectDetailScreen> createState() => _SubjectDetailScreenState();
}

class _SubjectDetailScreenState extends State<SubjectDetailScreen> {
  SubjectDetailModel? _detail;
  bool _loading = true;
  String? _error;
  final Set<int> _expanded = {};
  int? _savingTopicId;
  // Local hours overrides for optimistic header updates before backend save
  final Map<int, double> _localHoursMap = {};

  double get _localTotalHours {
    if (_detail == null) return 0;
    double total = 0;
    for (final ch in _detail!.chapters) {
      for (final t in ch.topics) {
        total += _localHoursMap[t.id] ?? t.actualHours;
      }
    }
    return total;
  }

  void _onLocalHoursChanged(int topicId, double hours) {
    setState(() => _localHoursMap[topicId] = hours);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = _detail == null);
    try {
      final detail =
          await GetIt.I<ProgressRepository>().getSubjectDetail(widget.subjectId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
        _localHoursMap.clear(); // fresh backend data — drop local overrides
        if (_expanded.isEmpty) {
          for (var i = 0; i < detail.chapters.length && i < 2; i++) {
            _expanded.add(detail.chapters[i].id);
          }
        }
      });
      AnalyticsService.logSubjectOpened(
        subjectId: detail.subjectId,
        subjectName: detail.subjectName,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _onTopicComplete(TopicModel topic, double hours) async {
    setState(() => _savingTopicId = topic.id);
    try {
      await GetIt.I<ProgressRepository>().markTopicComplete(
        topicId: topic.id,
        isCompleted: true,
        actualHours: hours,
      );
      // Log study hours so dashboard todayHours is updated
      if (hours > 0) {
        try {
          final prevHours = topic.actualHours;
          final delta = hours - prevHours;
          if (delta > 0) {
            await GetIt.I<ProgressRepository>().logStudyHours(
              studyDate: _localTodayDate(),
              hoursStudied: delta,
            );
          }
        } catch (_) {} // non-critical
      }
      await _load(silent: true);
      if (!mounted) return;
      setState(() => _savingTopicId = null);
      if (mounted) {
        context.read<DashboardBloc>().add(DashboardRefreshRequested());
      }
      AnalyticsService.logTopicCompleted(
        topicId: topic.id,
        topicName: topic.title,
        subjectName: _detail?.subjectName ?? '',
        actualHours: hours,
      );
      _showSuccessDialog(topic.title, hours);
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingTopicId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _onHoursUpdated(TopicModel topic, double hours) async {
    if (hours == topic.actualHours) return;
    final delta = hours - topic.actualHours;
    try {
      await GetIt.I<ProgressRepository>().markTopicComplete(
        topicId: topic.id,
        isCompleted: false,
        actualHours: hours,
      );
      // Log positive delta so dashboard todayHours is updated
      if (delta > 0) {
        try {
          await GetIt.I<ProgressRepository>().logStudyHours(
            studyDate: _localTodayDate(),
            hoursStudied: delta,
          );
        } catch (_) {} // non-critical
      }
      _load(silent: true);
      if (mounted) {
        context.read<DashboardBloc>().add(DashboardRefreshRequested());
      }
      AnalyticsService.logStudyHoursAdded(
        hours: hours,
        subjectName: _detail?.subjectName ?? '',
      );
    } catch (_) {}
  }

  void _showSuccessDialog(String title, double hours) {
    showDialog(
      context: context,
      builder: (_) => _SuccessDialog(topicTitle: title, hours: hours),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off_rounded,
                  size: 64, color: AppColors.textHint),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _load();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final d = _detail!;
    final color = d.color;
    final pct = d.completionPercent / 100;

    final isDesktop = ResponsiveHelper.isDesktop(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isDesktop ? 860 : double.infinity,
          ),
          child: CustomScrollView(
            slivers: [
          // ── Gradient Header ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: _SubjectHeader(
              detail: d,
              color: color,
              pct: pct,
              localTotalHours: _localTotalHours,
            ),
          ),

          // ── "Topics" Label ───────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Topics',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${d.totalTopics} Topics',
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w600,
                          fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Chapter List ─────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ChapterCard(
                    chapter: d.chapters[i],
                    subjectColor: color,
                    isExpanded: _expanded.contains(d.chapters[i].id),
                    savingTopicId: _savingTopicId,
                    onToggle: () => setState(() {
                      final id = d.chapters[i].id;
                      if (_expanded.contains(id)) {
                        _expanded.remove(id);
                      } else {
                        _expanded.add(id);
                      }
                    }),
                    onTopicComplete: _onTopicComplete,
                    onHoursUpdated: _onHoursUpdated,
                    onLocalHoursChanged: _onLocalHoursChanged,
                  ),
                ),
                childCount: d.chapters.length,
              ),
            ),
          ),

          // ── Tip Card ─────────────────────────────────────────────────
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 80),
              child: _TipCard(),
            ),
          ),
        ],
          ),
        ),
      ),
    );
  }
}

// ─── Subject Header ─────────────────────────────────────────────────────────
class _SubjectHeader extends StatelessWidget {
  final SubjectDetailModel detail;
  final Color color;
  final double pct;
  final double localTotalHours;
  const _SubjectHeader(
      {required this.detail,
      required this.color,
      required this.pct,
      required this.localTotalHours});

  @override
  Widget build(BuildContext context) {
    String statusLabel = '';
    Color statusBg = Colors.transparent;
    if (pct >= 1.0) {
      statusLabel = 'Completed';
      statusBg = const Color(0xFF43D854);
    } else if (pct > 0) {
      statusLabel = 'In Progress';
      statusBg = const Color(0xFFFF8C00);
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, Colors.black, 0.28)!],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 16, 24),
          child: Column(
            children: [
              // Top bar
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 20),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: Text(
                      detail.subjectName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.menu_book_outlined,
                      color: Colors.white, size: 22),
                  const SizedBox(width: 8),
                ],
              ),

              const SizedBox(height: 20),

              // Big circular progress
              SizedBox(
                width: 140,
                height: 140,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 140,
                      height: 140,
                      child: CircularProgressIndicator(
                        value: pct,
                        strokeWidth: 10,
                        backgroundColor: Colors.white.withOpacity(0.2),
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(Colors.white),
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (statusLabel.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 3),
                            margin: const EdgeInsets.only(bottom: 4),
                            decoration: BoxDecoration(
                              color: statusBg,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(statusLabel,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700)),
                          ),
                        Text(
                          '${detail.completionPercent.toStringAsFixed(0)}%',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              Text(
                '${detail.completedTopics} / ${detail.totalTopics} topics completed',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              Text(
                '${localTotalHours.toStringAsFixed(1)}h studied',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.8), fontSize: 13),
              ),

              const SizedBox(height: 16),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 6,
                    backgroundColor: Colors.white.withOpacity(0.25),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Stat chips
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    _HeaderChip(
                        icon: Icons.layers_rounded,
                        label: '${detail.chapters.length} Chapters'),
                    const SizedBox(width: 8),
                    _HeaderChip(
                        icon: Icons.check_circle_outline_rounded,
                        label: '${detail.completedTopics} Done'),
                    const SizedBox(width: 8),
                    _HeaderChip(
                        icon: Icons.timer_rounded,
                        label:
                            '${localTotalHours.toStringAsFixed(1)}h studied'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _HeaderChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding:
            const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 13),
            const SizedBox(width: 4),
            Flexible(
              child: Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 11),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Tip Card ────────────────────────────────────────────────────────────────
class _TipCard extends StatelessWidget {
  const _TipCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD54F)),
      ),
      child: const Row(
        children: [
          Text('💡', style: TextStyle(fontSize: 18)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tip: Add study hours first, then mark topic as completed.',
              style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF795548),
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Chapter Card ────────────────────────────────────────────────────────────
class _ChapterCard extends StatelessWidget {
  final ChapterDetailModel chapter;
  final Color subjectColor;
  final bool isExpanded;
  final int? savingTopicId;
  final VoidCallback onToggle;
  final Future<void> Function(TopicModel, double) onTopicComplete;
  final Future<void> Function(TopicModel, double) onHoursUpdated;
  final void Function(int topicId, double hours) onLocalHoursChanged;

  const _ChapterCard({
    required this.chapter,
    required this.subjectColor,
    required this.isExpanded,
    required this.savingTopicId,
    required this.onToggle,
    required this.onTopicComplete,
    required this.onHoursUpdated,
    required this.onLocalHoursChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          // Chapter header
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Circular progress indicator
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: chapter.completionPercent / 100,
                          strokeWidth: 4,
                          backgroundColor:
                              subjectColor.withOpacity(0.15),
                          valueColor: AlwaysStoppedAnimation<Color>(
                              subjectColor),
                          strokeCap: StrokeCap.round,
                        ),
                        Text(
                          '${chapter.completionPercent.toStringAsFixed(0)}%',
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: subjectColor),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(chapter.title,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: AppColors.textPrimary)),
                        const SizedBox(height: 3),
                        Text(
                          '${chapter.completedTopics}/${chapter.totalTopics} topics completed',
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textHint,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),

          // Topic list (animated expand/collapse)
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: [
                Divider(
                    height: 1,
                    thickness: 0.5,
                    color: Colors.grey.shade200),
                ...chapter.topics.map(
                  (topic) => _TopicTile(
                    key: ValueKey(topic.id),
                    topic: topic,
                    subjectColor: subjectColor,
                    isSaving: savingTopicId == topic.id,
                    onTopicComplete: onTopicComplete,
                    onHoursUpdated: onHoursUpdated,
                    onLocalHoursChanged: onLocalHoursChanged,
                  ),
                ),
                const SizedBox(height: 6),
              ],
            ),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
          ),
        ],
      ),
    );
  }
}

// ─── Hours auto-save status ───────────────────────────────────────────────────
enum _HoursSaveStatus { idle, saving, saved }

// ─── Topic Tile ──────────────────────────────────────────────────────────────
class _TopicTile extends StatefulWidget {
  final TopicModel topic;
  final Color subjectColor;
  final bool isSaving;
  final Future<void> Function(TopicModel, double) onTopicComplete;
  final Future<void> Function(TopicModel, double) onHoursUpdated;
  final void Function(int topicId, double hours) onLocalHoursChanged;

  const _TopicTile({
    super.key,
    required this.topic,
    required this.subjectColor,
    required this.isSaving,
    required this.onTopicComplete,
    required this.onHoursUpdated,
    required this.onLocalHoursChanged,
  });

  @override
  State<_TopicTile> createState() => _TopicTileState();
}

class _TopicTileState extends State<_TopicTile> {
  double _localHours = 0;
  bool _showStepper = false;
  Timer? _debounce;
  _HoursSaveStatus _hoursSaveStatus = _HoursSaveStatus.idle;
  Timer? _savedResetTimer;

  @override
  void initState() {
    super.initState();
    _localHours = widget.topic.actualHours;
    _showStepper = _statusOf(widget.topic) == _TopicStatus.inProgress;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _savedResetTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(_TopicTile old) {
    super.didUpdateWidget(old);
    if (old.topic.actualHours != widget.topic.actualHours ||
        old.topic.isCompleted != widget.topic.isCompleted) {
      _localHours = widget.topic.actualHours;
      _showStepper = _statusOf(widget.topic) == _TopicStatus.inProgress;
    }
  }

  Color get _diffColor {
    switch (widget.topic.difficultyLevel) {
      case 'EASY':
        return const Color(0xFF43A047);
      case 'HARD':
        return const Color(0xFFE53935);
      default:
        return const Color(0xFFFF6B35);
    }
  }

  void _inc() {
    setState(() => _localHours = (_localHours + 0.5).clamp(0.0, 999.0));
    widget.onLocalHoursChanged(widget.topic.id, _localHours);
    _scheduleHoursSave();
  }

  void _dec() {
    if (_localHours > 0.5) {
      setState(() => _localHours -= 0.5);
      widget.onLocalHoursChanged(widget.topic.id, _localHours);
      _scheduleHoursSave();
    }
  }

  void _scheduleHoursSave() {
    _debounce?.cancel();
    _savedResetTimer?.cancel();
    setState(() => _hoursSaveStatus = _HoursSaveStatus.idle);
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      if (!mounted) return;
      setState(() => _hoursSaveStatus = _HoursSaveStatus.saving);
      await widget.onHoursUpdated(widget.topic, _localHours);
      if (!mounted) return;
      setState(() => _hoursSaveStatus = _HoursSaveStatus.saved);
      _savedResetTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _hoursSaveStatus = _HoursSaveStatus.idle);
      });
    });
  }

  Future<void> _onAddStudyHours() async {
    setState(() {
      _showStepper = true;
      if (_localHours < 0.5) _localHours = 0.5;
    });
    widget.onLocalHoursChanged(widget.topic.id, _localHours);
    widget.onHoursUpdated(widget.topic, _localHours);
  }

  void _showConfirm() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: widget.subjectColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.assignment_turned_in_outlined,
                    color: widget.subjectColor, size: 38),
              ),
              const SizedBox(height: 18),
              const Text('Mark as Completed?',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 12),
              Text(
                'You have logged ${_fmtH(_localHours)} for this topic.\n\nAre you sure you want to mark this topic as completed?',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.6),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        side: const BorderSide(
                            color: AppColors.textHint),
                      ),
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Cancel',
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.subjectColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding:
                            const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        widget.onTopicComplete(
                            widget.topic, _localHours);
                      },
                      child: const Text('Yes, Complete',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status =
        _showStepper ? _TopicStatus.inProgress : _statusOf(widget.topic);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: _buildContent(status),
    );
  }

  Widget _buildContent(_TopicStatus status) {
    switch (status) {
      case _TopicStatus.completed:
        return _completedTile();
      case _TopicStatus.inProgress:
        return _inProgressTile();
      case _TopicStatus.notStarted:
        return _notStartedTile();
    }
  }

  // ── NOT_STARTED ────────────────────────────────────────────────────
  Widget _notStartedTile() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 3),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: Colors.grey.shade300, width: 2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.topic.title,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 6),
                    _diffRow(),
                  ],
                ),
              ),
              if (widget.isSaving)
                const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: Icon(Icons.add_rounded,
                color: widget.subjectColor, size: 18),
            label: Text('+ Add Study Hours',
                style: TextStyle(
                    color: widget.subjectColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 42),
              side: BorderSide(
                  color: widget.subjectColor.withOpacity(0.5),
                  width: 1.2),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: widget.isSaving ? null : _onAddStudyHours,
          ),
          const SizedBox(height: 10),
          Divider(thickness: 0.5, height: 1, color: Colors.grey.shade200),
        ],
      ),
    );
  }

  // ── IN_PROGRESS ───────────────────────────────────────────────────
  Widget _inProgressTile() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  value: 0.5,
                  strokeWidth: 2.5,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                      widget.subjectColor),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.topic.title,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 6),
                    _diffRow(),
                  ],
                ),
              ),
              if (widget.isSaving)
                const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 14),
          const Text('Hours Studied',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          // Hours stepper
          Row(
            children: [
              _stepBtn(Icons.remove_rounded,
                  _localHours > 0.5 ? _dec : null),
              const SizedBox(width: 14),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: widget.subjectColor.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color:
                            widget.subjectColor.withOpacity(0.2)),
                  ),
                  child: Text(
                    _fmtH(_localHours),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: widget.subjectColor),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              _stepBtn(Icons.add_rounded, _inc),
            ],
          ),
          const SizedBox(height: 8),
          // Auto-save status indicator
          if (_hoursSaveStatus == _HoursSaveStatus.saving)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: widget.subjectColor.withOpacity(0.7))),
                const SizedBox(width: 6),
                Text('Saving…',
                    style: TextStyle(
                        fontSize: 11,
                        color: widget.subjectColor.withOpacity(0.7))),
              ],
            )
          else if (_hoursSaveStatus == _HoursSaveStatus.saved)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline,
                    size: 12,
                    color: const Color(0xFF43A047).withOpacity(0.85)),
                const SizedBox(width: 4),
                Text('Saved',
                    style: TextStyle(
                        fontSize: 11,
                        color: const Color(0xFF43A047).withOpacity(0.85))),
              ],
            )
          else
            const SizedBox(height: 2),
          const SizedBox(height: 8),
          // Mark completed button
          ElevatedButton.icon(
            icon: widget.isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_circle_outline_rounded,
                    size: 18),
            label: const Text('Mark as Completed',
                style: TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 14)),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 46),
              backgroundColor: widget.subjectColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: widget.isSaving ? null : _showConfirm,
          ),
          const SizedBox(height: 10),
          Divider(thickness: 0.5, height: 1, color: Colors.grey.shade200),
        ],
      ),
    );
  }

  // ── COMPLETED ────────────────────────────────────────────────────
  Widget _completedTile() {
    final completedAt = widget.topic.completedAt;
    String timeStr = '';
    if (completedAt != null && completedAt.isNotEmpty) {
      try {
        final dt = _parseBackendTimestamp(completedAt);
        final now = DateTime.now();
        final isToday = dt.year == now.year &&
            dt.month == now.month &&
            dt.day == now.day;
        final tf = DateFormat.jm().format(dt);
        timeStr = isToday
            ? 'Today • $tf'
            : '${DateFormat('d MMM').format(dt)} • $tf';
      } catch (_) {}
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF43D854).withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: const Color(0xFF43D854).withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: Color(0xFF43D854), size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(widget.topic.title,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: _diffRow(),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF43D854).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_rounded,
                            color: Color(0xFF43D854), size: 12),
                        SizedBox(width: 4),
                        Text('Completed',
                            style: TextStyle(
                                color: Color(0xFF43D854),
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  if (widget.topic.actualHours > 0) ...[
                    const SizedBox(width: 8),
                    Text(
                        '${_fmtH(widget.topic.actualHours)} studied',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary)),
                  ],
                ],
              ),
            ),
            if (timeStr.isNotEmpty) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: Text(timeStr,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textHint)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _diffRow() {
    return Row(
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: _diffColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(widget.topic.difficultyLevel,
              style: TextStyle(
                  fontSize: 10,
                  color: _diffColor,
                  fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 8),
        const Icon(Icons.schedule_rounded,
            size: 12, color: AppColors.textHint),
        const SizedBox(width: 3),
        Text(
            '${widget.topic.estimatedHours.toStringAsFixed(0)}h est.',
            style: const TextStyle(
                fontSize: 11, color: AppColors.textHint)),
      ],
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback? onTap) {
    final active = onTap != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? widget.subjectColor.withOpacity(0.1)
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active
                  ? widget.subjectColor.withOpacity(0.3)
                  : Colors.grey.shade300,
            ),
          ),
          child: Icon(icon,
              size: 20,
              color: active
                  ? widget.subjectColor
                  : Colors.grey.shade400),
        ),
      ),
    );
  }
}

// ─── Success Dialog ──────────────────────────────────────────────────────────
class _SuccessDialog extends StatelessWidget {
  final String topicTitle;
  final double hours;
  const _SuccessDialog({required this.topicTitle, required this.hours});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 90,
                height: 90,
              decoration: BoxDecoration(
                color: const Color(0xFF43D854).withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF43D854), size: 62),
            ),
            const SizedBox(height: 20),
            const Text('Great! Topic Completed',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    height: 1.5),
                children: [
                  const TextSpan(text: 'You have completed\n'),
                  TextSpan(
                      text: '"$topicTitle"',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  const TextSpan(text: '.'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_fmtH(hours)} of study time saved.',
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF43D854)),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF43D854),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

