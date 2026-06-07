import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/firebase/analytics_service.dart';
import '../../../core/utils/responsive_helper.dart';
import '../../../data/models/subject_detail_model.dart';
import '../../../data/models/mock_test_model.dart';
import '../../../data/models/topic_model.dart';
import '../../../data/repositories/mock_test_repository.dart';
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

String _fmtDuration(double hours) {
  if (hours <= 0) return '0m';
  final totalMinutes = (hours * 60).round();
  final h = totalMinutes ~/ 60;
  final m = totalMinutes % 60;
  if (h > 0 && m > 0) return '${h}h ${m}m';
  if (h > 0) return '${h}h';
  return '${m}m';
}

enum _TopicFilter { all, completed, inProgress, notStarted }

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
  final int userExamId;

  const SubjectDetailScreen({
    super.key,
    required this.subjectId,
    required this.userExamId,
  });

  @override
  State<SubjectDetailScreen> createState() => _SubjectDetailScreenState();
}

class _SubjectDetailScreenState extends State<SubjectDetailScreen> {
  SubjectDetailModel? _detail;
  bool _loading = true;
  String? _error;
  int? _savingTopicId;
  _TopicFilter _topicFilter = _TopicFilter.all;
  final Map<int, double> _localHoursMap = {};

  List<TopicModel> get _allTopics {
    if (_detail == null) return [];
    return _detail!.chapters.expand((chapter) => chapter.topics).toList();
  }

  int get _liveTotalTopics => _allTopics.length;

  int get _liveCompletedTopics => _allTopics
      .where((topic) => _statusOf(topic) == _TopicStatus.completed)
      .length;

  double get _liveCompletionPercent => _liveTotalTopics == 0
      ? 0.0
      : (_liveCompletedTopics * 100.0 / _liveTotalTopics);

  List<TopicModel> get _filteredTopics {
    return _allTopics.where((topic) {
      final status = _statusOf(topic);
      return switch (_topicFilter) {
        _TopicFilter.all => true,
        _TopicFilter.completed => status == _TopicStatus.completed,
        _TopicFilter.inProgress => status == _TopicStatus.inProgress,
        _TopicFilter.notStarted => status == _TopicStatus.notStarted,
      };
    }).toList();
  }

  double _topicHours(TopicModel topic) =>
      _localHoursMap[topic.id] ?? topic.actualHours;

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

  Future<void> _applyLocalTopicUpdate({
    required TopicModel topic,
    required double hours,
    required bool isCompleted,
  }) async {
    final repo = GetIt.I<ProgressRepository>();
    final updated = await repo.patchTopicInCache(
      userExamId: widget.userExamId,
      subjectId: widget.subjectId,
      topicId: topic.id,
      actualHours: hours,
      isCompleted: isCompleted,
      status: isCompleted ? 'COMPLETED' : (hours > 0 ? 'IN_PROGRESS' : topic.status),
    );
    if (!mounted || updated == null) return;
    setState(() {
      _detail = updated;
      _localHoursMap[topic.id] = hours;
    });
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = _detail == null);
    try {
      final detail = await GetIt.I<ProgressRepository>().getSubjectDetail(
        widget.subjectId,
        userExamId: widget.userExamId,
        forceRemote: false,
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
        _localHoursMap.clear();
        _error = null;
      });
      AnalyticsService.logSubjectOpened(
        subjectId: detail.subjectId,
        subjectName: detail.subjectName,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _detail == null ? e.toString() : null;
        _loading = false;
      });
    }
  }

  Future<void> _onTopicComplete(TopicModel topic, double hours) async {
    final prevHours = topic.actualHours;
    final delta = hours - prevHours;

    await _applyLocalTopicUpdate(
      topic: topic,
      hours: hours,
      isCompleted: true,
    );
    if (!mounted) return;

    _showSuccessDialog(topic.title, hours);

    await GetIt.I<ProgressRepository>().persistTopicProgress(
      userExamId: widget.userExamId,
      subjectId: widget.subjectId,
      topicId: topic.id,
      wasCompleted: topic.isCompleted,
      isCompleted: true,
      actualHours: hours,
      studyHoursDelta: delta != 0 ? delta : null,
      studyDate: _localTodayDate(),
    );
    if (mounted) {
      context.read<DashboardBloc>().add(DashboardRefreshRequested());
    }

    AnalyticsService.logTopicCompleted(
      topicId: topic.id,
      topicName: topic.title,
      subjectName: _detail?.subjectName ?? '',
      actualHours: hours,
    );
  }

  Future<void> _onHoursUpdated(TopicModel topic, double hours) async {
    if (hours == topic.actualHours) return;
    final delta = hours - topic.actualHours;

    await _applyLocalTopicUpdate(
      topic: topic,
      hours: hours,
      isCompleted: topic.isCompleted,
    );
    if (!mounted) return;

    await GetIt.I<ProgressRepository>().persistTopicProgress(
      userExamId: widget.userExamId,
      subjectId: widget.subjectId,
      topicId: topic.id,
      wasCompleted: topic.isCompleted,
      isCompleted: topic.isCompleted,
      actualHours: hours,
      studyHoursDelta: delta != 0 ? delta : null,
      studyDate: _localTodayDate(),
    );
    if (mounted) {
      context.read<DashboardBloc>().add(DashboardRefreshRequested());
    }

    AnalyticsService.logStudyHoursAdded(
      hours: hours,
      subjectName: _detail?.subjectName ?? '',
    );
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
    final pct = _liveCompletionPercent / 100;
    final completedTopics = _liveCompletedTopics;
    final totalTopics = _liveTotalTopics;

    final isDesktop = ResponsiveHelper.isDesktop(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: Text(
          d.subjectName,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert_rounded),
            onPressed: () {},
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isDesktop ? 860 : double.infinity,
          ),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: _ProgressSection(
                    detail: d,
                    color: color,
                    pct: pct,
                    completedTopics: completedTopics,
                    totalTopics: totalTopics,
                    completionPercent: _liveCompletionPercent,
                    localTotalHours: _localTotalHours,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        'Topics ($totalTopics)',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: _showTopicFilter,
                        icon: const Icon(Icons.filter_list_rounded, size: 18),
                        label: Text(_topicFilterLabel),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          side: const BorderSide(color: Color(0xFFE5E7EB)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      final topic = _filteredTopics[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _TopicTile(
                          key: ValueKey(topic.id),
                          topic: topic,
                          subjectColor: color,
                          localHours: _topicHours(topic),
                          isSaving: _savingTopicId == topic.id,
                          onTopicComplete: _onTopicComplete,
                          onHoursUpdated: _onHoursUpdated,
                          onLocalHoursChanged: _onLocalHoursChanged,
                        ),
                      );
                    },
                    childCount: _filteredTopics.length,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _topicFilterLabel => switch (_topicFilter) {
        _TopicFilter.all => 'Filter',
        _TopicFilter.completed => 'Completed',
        _TopicFilter.inProgress => 'In Progress',
        _TopicFilter.notStarted => 'Not Started',
      };

  void _showTopicFilter() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Filter Topics',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            for (final filter in _TopicFilter.values)
              ListTile(
                title: Text(_filterName(filter)),
                trailing: _topicFilter == filter
                    ? Icon(Icons.check_rounded, color: _detail?.color ?? AppColors.primary)
                    : null,
                onTap: () {
                  setState(() => _topicFilter = filter);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }

  String _filterName(_TopicFilter filter) => switch (filter) {
        _TopicFilter.all => 'All Topics',
        _TopicFilter.completed => 'Completed',
        _TopicFilter.inProgress => 'In Progress',
        _TopicFilter.notStarted => 'Not Started',
      };
}

// ─── Progress Section ───────────────────────────────────────────────────────
class _ProgressSection extends StatelessWidget {
  final SubjectDetailModel detail;
  final Color color;
  final double pct;
  final int completedTopics;
  final int totalTopics;
  final double completionPercent;
  final double localTotalHours;

  const _ProgressSection({
    required this.detail,
    required this.color,
    required this.pct,
    required this.completedTopics,
    required this.totalTopics,
    required this.completionPercent,
    required this.localTotalHours,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8EBF0)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: pct,
                          strokeWidth: 7,
                          backgroundColor: const Color(0xFFEEF0F5),
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                          strokeCap: StrokeCap.round,
                        ),
                        Text(
                          '${completionPercent.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Your Progress',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '$completedTopics / $totalTopics Topics Completed',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_fmtDuration(localTotalHours)} Studied',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 5,
                  backgroundColor: const Color(0xFFEEF0F5),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _StatCard(
              icon: Icons.menu_book_outlined,
              iconColor: color,
              value: '${detail.chapters.length}',
              label: 'Chapter',
            ),
            const SizedBox(width: 10),
            _StatCard(
              icon: Icons.check_circle_outline_rounded,
              iconColor: const Color(0xFF43A047),
              value: '$completedTopics',
              label: 'Completed',
            ),
            const SizedBox(width: 10),
            _StatCard(
              icon: Icons.schedule_rounded,
              iconColor: AppColors.primary,
              value: _fmtDuration(localTotalHours),
              label: 'Studied',
            ),
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE8EBF0)),
        ),
        child: Column(
          children: [
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Topic Tile ──────────────────────────────────────────────────────────────
class _TopicTile extends StatefulWidget {
  final TopicModel topic;
  final Color subjectColor;
  final double localHours;
  final bool isSaving;
  final Future<void> Function(TopicModel, double) onTopicComplete;
  final Future<void> Function(TopicModel, double) onHoursUpdated;
  final void Function(int topicId, double hours) onLocalHoursChanged;

  const _TopicTile({
    super.key,
    required this.topic,
    required this.subjectColor,
    required this.localHours,
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
  MockTestInfoModel? _mockTestInfo;
  bool _loadingMockTest = true;

  @override
  void initState() {
    super.initState();
    _localHours = widget.localHours;
    _showStepper = _statusOf(widget.topic) == _TopicStatus.inProgress;
    _loadMockTestInfo();
  }

  Future<void> _loadMockTestInfo() async {
    try {
      final info = await GetIt.I<MockTestRepository>().getTopicInfo(
        widget.topic.id,
        forceRemote: false,
      );
      if (mounted) {
        setState(() {
          _mockTestInfo = info.isConfigured && info.isActive ? info : null;
          _loadingMockTest = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMockTest = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(_TopicTile old) {
    super.didUpdateWidget(old);
    if (old.topic.actualHours != widget.topic.actualHours ||
        old.topic.isCompleted != widget.topic.isCompleted ||
        old.localHours != widget.localHours) {
      _localHours = widget.localHours;
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
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      if (!mounted) return;
      await widget.onHoursUpdated(widget.topic, _localHours);
    });
  }

  Future<void> _onAddStudyHours() async {
    setState(() {
      _showStepper = true;
      if (_localHours < 0.5) _localHours = 0.5;
    });
    widget.onLocalHoursChanged(widget.topic.id, _localHours);
    if (_localHours != widget.topic.actualHours) {
      _scheduleHoursSave();
    }
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

  double get _topicProgress {
    final status =
        _showStepper ? _TopicStatus.inProgress : _statusOf(widget.topic);
    return switch (status) {
      _TopicStatus.completed => 1.0,
      _TopicStatus.inProgress => widget.topic.estimatedHours > 0
          ? (_localHours / widget.topic.estimatedHours).clamp(0.0, 1.0)
          : 0.5,
      _TopicStatus.notStarted => 0.0,
    };
  }

  String get _statusText {
    final status =
        _showStepper ? _TopicStatus.inProgress : _statusOf(widget.topic);
    return switch (status) {
      _TopicStatus.completed =>
        'Completed • ${_fmtDuration(widget.topic.actualHours)} studied',
      _TopicStatus.inProgress =>
        '${(_topicProgress * 100).round()}% completed • ${_fmtDuration(_localHours)} studied',
      _TopicStatus.notStarted => '0% completed',
    };
  }

  Widget _compactAddHoursButton() {
    return OutlinedButton.icon(
      onPressed: widget.isSaving ? null : _onAddStudyHours,
      icon: Icon(Icons.add_rounded, size: 16, color: widget.subjectColor),
      label: Text(
        'Add Hours',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: widget.subjectColor,
        ),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        side: BorderSide(color: widget.subjectColor.withValues(alpha: 0.35)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _hoursStepperSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Hours Studied',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _stepBtn(Icons.remove_rounded, _localHours > 0.5 ? _dec : null),
            const SizedBox(width: 14),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: widget.subjectColor.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: widget.subjectColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  _fmtH(_localHours),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: widget.subjectColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            _stepBtn(Icons.add_rounded, _inc),
          ],
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: widget.isSaving ? null : _showConfirm,
          icon: widget.isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check_circle_outline_rounded, size: 18),
          label: const Text(
            'Mark as Completed',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 46),
            backgroundColor: widget.subjectColor,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusIcon(_TopicStatus status) {
    if (status == _TopicStatus.completed) {
      return const Icon(
        Icons.check_circle_rounded,
        color: Color(0xFF43A047),
        size: 24,
      );
    }
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey.shade300, width: 2),
      ),
    );
  }

  Widget _compactStartTestButton() {
    if (_loadingMockTest || _mockTestInfo == null) {
      return const SizedBox.shrink();
    }

    final info = _mockTestInfo!;
    final canStart = info.canStart;

    return FilledButton.icon(
      onPressed: canStart
          ? () {
              final title = Uri.encodeComponent(widget.topic.title);
              context.push('/mock-test/${widget.topic.id}?title=$title');
            }
          : null,
      icon: const Icon(Icons.quiz_outlined, size: 16),
      label: Text(canStart ? 'Start Test' : 'Unavailable'),
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF43A047),
        disabledBackgroundColor: Colors.grey.shade300,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Widget _actionButtonsRow(_TopicStatus status) {
    final showAddHours = status == _TopicStatus.notStarted && !_showStepper;
    if (!showAddHours) {
      return const SizedBox.shrink();
    }

    return Align(
      alignment: Alignment.centerRight,
      child: _compactAddHoursButton(),
    );
  }

  Widget _completedStartTestSection() {
    if (_loadingMockTest || _mockTestInfo == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: _compactStartTestButton(),
        ),
        if (!_mockTestInfo!.canStart)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Only ${_mockTestInfo!.availableQuestionCount} of ${_mockTestInfo!.numQuestions} questions available.',
              style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
              textAlign: TextAlign.right,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final status =
        _showStepper ? _TopicStatus.inProgress : _statusOf(widget.topic);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EBF0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: _statusIcon(status),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.topic.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _diffRow(),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _topicProgress,
                minHeight: 5,
                backgroundColor: const Color(0xFFEEF0F5),
                valueColor: AlwaysStoppedAnimation<Color>(
                  status == _TopicStatus.completed
                      ? const Color(0xFF43A047)
                      : widget.subjectColor,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _statusText,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            if (status == _TopicStatus.completed &&
                _completedTimeLabel.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                _completedTimeLabel,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textHint,
                ),
              ),
            ],
            if (status != _TopicStatus.completed) ...[
              const SizedBox(height: 12),
              _actionButtonsRow(status),
            ] else ...[
              const SizedBox(height: 12),
              _completedStartTestSection(),
            ],
            if (_showStepper && status != _TopicStatus.completed) ...[
              const SizedBox(height: 16),
              _hoursStepperSection(),
            ],
          ],
        ),
      ),
    );
  }

  String get _completedTimeLabel {
    final completedAt = widget.topic.completedAt;
    if (completedAt == null || completedAt.isEmpty) return '';
    try {
      final dt = _parseBackendTimestamp(completedAt);
      final now = DateTime.now();
      final isToday = dt.year == now.year &&
          dt.month == now.month &&
          dt.day == now.day;
      final tf = DateFormat.jm().format(dt);
      return isToday
          ? 'Today • $tf'
          : '${DateFormat('d MMM').format(dt)} • $tf';
    } catch (_) {
      return '';
    }
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

