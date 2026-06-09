import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

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

bool _isSelectable(TopicModel t) => _statusOf(t) != _TopicStatus.completed;

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
  bool _bulkSaving = false;
  bool _selectionMode = false;
  final Set<int> _selectedTopicIds = {};
  double _selectionStudyHours = 0;
  _TopicFilter _topicFilter = _TopicFilter.all;

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

  double get _localTotalHours {
    if (_detail == null) return 0;
    double total = 0;
    for (final ch in _detail!.chapters) {
      for (final t in ch.topics) {
        total += t.actualHours;
      }
    }
    return total;
  }

  List<TopicModel> get _selectedTopics => _filteredTopics
      .where((topic) => _selectedTopicIds.contains(topic.id))
      .toList();

  void _enterSelectionMode([TopicModel? initial]) {
    setState(() {
      _selectionMode = true;
      _selectedTopicIds.clear();
      if (initial != null && _isSelectable(initial)) {
        _selectedTopicIds.add(initial.id);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedTopicIds.clear();
      _selectionStudyHours = 0;
    });
  }

  void _toggleTopicSelection(TopicModel topic) {
    if (!_isSelectable(topic)) return;
    setState(() {
      if (_selectedTopicIds.contains(topic.id)) {
        _selectedTopicIds.remove(topic.id);
        if (_selectedTopicIds.isEmpty) _selectionMode = false;
      } else {
        _selectedTopicIds.add(topic.id);
      }
    });
  }

  void _onTopicTap(TopicModel topic) {
    if (_selectionMode) {
      if (!_isSelectable(topic)) return;
      _toggleTopicSelection(topic);
      return;
    }
    if (_statusOf(topic) == _TopicStatus.completed) {
      _showCompletedTopicSheet(topic);
      return;
    }
    _enterSelectionMode(topic);
  }

  void _onTopicLongPress(TopicModel topic) {
    if (!_isSelectable(topic)) {
      if (!_selectionMode) _showCompletedTopicSheet(topic);
      return;
    }
    if (!_selectionMode) {
      _enterSelectionMode(topic);
    } else {
      _toggleTopicSelection(topic);
    }
  }

  Future<void> _bulkMarkCompleted() async {
    final topics = _selectedTopics;
    if (topics.isEmpty) return;

    final alreadyDone = topics.every((topic) => topic.isCompleted);
    if (alreadyDone && _selectionStudyHours <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selected topics are already completed'),
        ),
      );
      return;
    }

    setState(() => _bulkSaving = true);
    final loggedHours = _selectionStudyHours;
    try {
      final count =
          await GetIt.I<ProgressRepository>().bulkCompleteSelectedTopics(
        userExamId: widget.userExamId,
        subjectId: widget.subjectId,
        topics: topics,
        totalStudyHours: loggedHours,
        studyDate: _localTodayDate(),
      );
      await _load(silent: true);
      _exitSelectionMode();
      if (!mounted) return;

      final hoursPart =
          loggedHours > 0 ? ' · ${_fmtH(loggedHours)} logged' : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count > 0
                ? '$count topic${count == 1 ? '' : 's'} marked completed$hoursPart'
                : 'Study hours updated$hoursPart',
          ),
        ),
      );
      context.read<DashboardBloc>().add(DashboardRefreshRequested());
    } finally {
      if (mounted) setState(() => _bulkSaving = false);
    }
  }

  void _showCompletedTopicSheet(TopicModel topic) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _CompletedTopicSheet(
        topic: topic,
        subjectColor: _detail!.color,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
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
          _selectionMode
              ? '${_selectedTopicIds.length} selected'
              : d.subjectName,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(
            _selectionMode
                ? Icons.close_rounded
                : Icons.arrow_back_ios_new_rounded,
            size: 20,
          ),
          onPressed: () {
            if (_selectionMode) {
              _exitSelectionMode();
            } else {
              Navigator.of(context).maybePop();
            }
          },
        ),
        actions: [
          if (!_selectionMode)
            IconButton(
              icon: const Icon(Icons.checklist_rounded),
              tooltip: 'Select topics',
              onPressed: () => _enterSelectionMode(),
            ),
        ],
      ),
      bottomNavigationBar: _selectedTopicIds.isNotEmpty
          ? _TopicSelectionPanel(
              studyHours: _selectionStudyHours,
              isSaving: _bulkSaving,
              subjectColor: color,
              onDecrement: () {
                if (_selectionStudyHours <= 0) return;
                setState(() =>
                    _selectionStudyHours = (_selectionStudyHours - 1.0)
                        .clamp(0.0, 999.0));
              },
              onIncrement: () => setState(
                () => _selectionStudyHours = (_selectionStudyHours + 1.0)
                    .clamp(0.0, 999.0),
              ),
              onMarkCompleted: _bulkMarkCompleted,
            )
          : null,
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
                padding: EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  _selectedTopicIds.isNotEmpty ? 200 : 80,
                ),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      final topic = _filteredTopics[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _TopicTile(
                          key: ValueKey(topic.id),
                          topic: topic,
                          subjectColor: color,
                          selectionMode: _selectionMode,
                          isSelectable: _isSelectable(topic),
                          isSelected: _selectedTopicIds.contains(topic.id),
                          onTap: () => _onTopicTap(topic),
                          onLongPress: () => _onTopicLongPress(topic),
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
class _TopicTile extends StatelessWidget {
  final TopicModel topic;
  final Color subjectColor;
  final bool selectionMode;
  final bool isSelectable;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _TopicTile({
    super.key,
    required this.topic,
    required this.subjectColor,
    required this.selectionMode,
    required this.isSelectable,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  double get _studyProgress {
    if (topic.isCompleted || topic.status == 'COMPLETED') return 1.0;
    if (topic.estimatedHours <= 0) return 0.0;
    return (topic.actualHours / topic.estimatedHours).clamp(0.0, 1.0);
  }

  String get _metaLine {
    final est = _fmtH(topic.estimatedHours);
    final studied = _fmtH(topic.actualHours);
    final pct = (_studyProgress * 100).round();
    return '$est est. • $studied studied • $pct%';
  }

  Widget _leadingIcon(_TopicStatus status) {
    if (status == _TopicStatus.completed) {
      return const Icon(
        Icons.check_circle_rounded,
        color: Color(0xFF43A047),
        size: 20,
      );
    }
    if (selectionMode) {
      return SizedBox(
        width: 22,
        height: 22,
        child: Checkbox(
          value: isSelected,
          onChanged: (_) => onTap(),
          activeColor: subjectColor,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
      );
    }
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey.shade400, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _statusOf(topic);
    final completed = status == _TopicStatus.completed;

    return Material(
      color: isSelected ? subjectColor.withValues(alpha: 0.06) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isSelectable ? onTap : null,
        onLongPress: isSelectable ? onLongPress : null,
        child: Opacity(
          opacity: selectionMode && completed ? 0.55 : 1,
          child: Container(
          height: 76,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected ? subjectColor : const Color(0xFFE8EBF0),
              width: isSelected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  _leadingIcon(status),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      topic.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Icon(
                    selectionMode && isSelectable
                        ? (isSelected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded)
                        : Icons.chevron_right_rounded,
                    size: 22,
                    color: isSelected ? subjectColor : Colors.grey.shade400,
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 13,
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _metaLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

class _TopicSelectionPanel extends StatelessWidget {
  static const _barHeight = 56.0;
  static const _ctaHeight = 46.0;
  static const _stepperMaxWidth = 132.0;

  final double studyHours;
  final bool isSaving;
  final Color subjectColor;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final VoidCallback onMarkCompleted;

  const _TopicSelectionPanel({
    required this.studyHours,
    required this.isSaving,
    required this.subjectColor,
    required this.onDecrement,
    required this.onIncrement,
    required this.onMarkCompleted,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          top: BorderSide(color: AppColors.divider, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.zero,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 380;
            final horizontalPad = compact ? 12.0 : 16.0;
            final stepperWidth = compact ? 118.0 : _stepperMaxWidth;

            return Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPad,
                8,
                horizontalPad,
                8,
              ),
              child: SizedBox(
                height: _barHeight,
                child: Row(
                  children: [
                    SizedBox(
                      width: stepperWidth,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _HourStepButton(
                            icon: Icons.remove_rounded,
                            enabled: !isSaving && studyHours > 0,
                            onTap: onDecrement,
                          ),
                          SizedBox(
                            width: compact ? 36 : 44,
                            child: Text(
                              _fmtH(studyHours),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: compact ? 15 : 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          _HourStepButton(
                            icon: Icons.add_rounded,
                            enabled: !isSaving,
                            onTap: onIncrement,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: compact ? 10 : 14),
                    Expanded(
                      child: SizedBox(
                        height: _ctaHeight,
                        child: FilledButton(
                          onPressed: isSaving ? null : onMarkCompleted,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.success,
                            disabledBackgroundColor:
                                AppColors.success.withValues(alpha: 0.45),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Mark Completed',
                                  maxLines: 1,
                                  overflow: TextOverflow.visible,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.1,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HourStepButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _HourStepButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? const Color(0xFFF3F4F6) : const Color(0xFFFAFAFA),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            icon,
            size: 18,
            color: enabled ? AppColors.textPrimary : AppColors.textHint,
          ),
        ),
      ),
    );
  }
}

class _CompletedTopicSheet extends StatefulWidget {
  final TopicModel topic;
  final Color subjectColor;

  const _CompletedTopicSheet({
    required this.topic,
    required this.subjectColor,
  });

  @override
  State<_CompletedTopicSheet> createState() => _CompletedTopicSheetState();
}

class _CompletedTopicSheetState extends State<_CompletedTopicSheet> {
  MockTestInfoModel? _mockTestInfo;
  bool _loadingMockTest = true;

  @override
  void initState() {
    super.initState();
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
  Widget build(BuildContext context) {
    final studied = _fmtH(widget.topic.actualHours);
    final est = _fmtH(widget.topic.estimatedHours);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.topic.title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$est est. • $studied studied • 100%',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          if (_loadingMockTest)
            const Center(child: CircularProgressIndicator())
          else if (_mockTestInfo != null)
            FilledButton.icon(
              onPressed: _mockTestInfo!.canStart
                  ? () {
                      Navigator.pop(context);
                      context.push('/topic-test/${widget.topic.id}');
                    }
                  : null,
              icon: const Icon(Icons.quiz_outlined),
              label: const Text('Start Mock Test'),
              style: FilledButton.styleFrom(
                backgroundColor: widget.subjectColor,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            )
          else
            const Text(
              'No mock test available for this topic.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }
}
