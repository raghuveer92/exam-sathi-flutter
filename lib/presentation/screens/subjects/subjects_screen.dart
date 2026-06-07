import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../core/firebase/analytics_service.dart';
import '../../../data/models/subject_model.dart';
import '../../../data/models/subject_progress_model.dart';
import '../../../data/models/user_exam_model.dart';
import '../../../data/repositories/dashboard_repository.dart';
import '../../widgets/sync_refresh_button.dart';

class SubjectsScreen extends StatefulWidget {
  const SubjectsScreen({super.key});

  @override
  State<SubjectsScreen> createState() => _SubjectsScreenState();
}

class _ExamSubjectsGroup {
  final UserExamModel exam;
  final List<SubjectModel> subjects;
  final double progress;
  final Map<int, SubjectProgressModel> progressBySubject;

  const _ExamSubjectsGroup({
    required this.exam,
    required this.subjects,
    required this.progress,
    required this.progressBySubject,
  });

  factory _ExamSubjectsGroup.fromCache(ExamSubjectsCacheGroup group) {
    final progressBySubject = <int, SubjectProgressModel>{
      for (final row in group.progressRows) row.subjectId: row,
    };
    final totalTopics =
        group.progressRows.fold<int>(0, (acc, e) => acc + e.totalTopics);
    final completedTopics =
        group.progressRows.fold<int>(0, (acc, e) => acc + e.completedTopics);
    final progress =
        totalTopics == 0 ? 0.0 : (completedTopics * 100.0 / totalTopics);

    return _ExamSubjectsGroup(
      exam: group.exam,
      subjects: group.subjects,
      progress: progress,
      progressBySubject: progressBySubject,
    );
  }
}

class _SubjectsScreenState extends State<SubjectsScreen> {
  final _repo = GetIt.I<DashboardRepository>();
  List<_ExamSubjectsGroup> _groups = const [];
  final Set<int> _expandedExamIds = <int>{};
  bool _loading = true;
  String? _error;

  static const List<Color> _examAccents = <Color>[
    Color(0xFF6C63FF),
    Color(0xFFFF8A00),
    Color(0xFF22A96B),
    Color(0xFF3B82F6),
  ];

  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView(screenName: 'SubjectsScreen');
    _loadFromLocal();
  }

  void _loadFromLocal() {
    _repo.buildSubjectGroupsFromCache().then((cached) {
      if (!mounted) return;
      final groups = cached.map(_ExamSubjectsGroup.fromCache).toList();
      setState(() {
        _groups = groups;
        _loading = false;
        _error = groups.isEmpty
            ? 'No subjects cached. Tap SYNC on Dashboard or Profile while online.'
            : null;
        if (_expandedExamIds.isEmpty && groups.isNotEmpty) {
          _expandedExamIds.addAll(groups.map((e) => e.exam.id));
        }
      });
    });
  }

  SubjectProgressModel? _progressFor(_ExamSubjectsGroup group, SubjectModel subject) {
    return group.progressBySubject[subject.id];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        title: const Text('Subjects'),
        actions: [
          SyncRefreshButton(onRefreshed: () async => _loadFromLocal()),
        ],
      ),
      body: _loading && _groups.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _groups.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error ?? 'No subjects in cache.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async => _loadFromLocal(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    children: [
                      for (var i = 0; i < _groups.length; i++) ...[
                        _buildExamSection(_groups[i], i),
                        const SizedBox(height: 14),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildExamSection(_ExamSubjectsGroup group, int index) {
    final accent = _examAccents[index % _examAccents.length];
    final isExpanded = _expandedExamIds.contains(group.exam.id);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7F2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedExamIds.remove(group.exam.id);
                } else {
                  _expandedExamIds.add(group.exam.id);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.description_outlined, color: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      group.exam.examName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${group.progress.toStringAsFixed(0)}% Complete',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
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
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1, color: Color(0xFFE9EAF3)),
            for (var i = 0; i < group.subjects.length; i++) ...[
              _buildSubjectRow(group, group.subjects[i], accent),
              if (i != group.subjects.length - 1)
                const Divider(height: 1, indent: 58, endIndent: 14, color: Color(0xFFEDEEF6)),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildSubjectRow(
    _ExamSubjectsGroup group,
    SubjectModel subject,
    Color accent,
  ) {
    final progress = _progressFor(group, subject);
    final completion = progress?.completionPercent ?? 0.0;
    final completedTopics = progress?.completedTopics ?? 0;
    final totalTopics = progress?.totalTopics ?? subject.topicCount;

    return InkWell(
      onTap: () async {
        if (!group.exam.isActive) {
          await _repo.setActiveMyExam(group.exam.id);
        }
        if (!mounted) return;
        await context.push('/subjects/exam/${group.exam.id}/${subject.id}');
        if (!mounted) return;
        _loadFromLocal();
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.menu_book_outlined, size: 17, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                subject.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '${completion.toStringAsFixed(0)}%',
              style: TextStyle(fontWeight: FontWeight.w700, color: accent),
            ),
            const SizedBox(width: 10),
            Text('$completedTopics/$totalTopics topics'),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}
