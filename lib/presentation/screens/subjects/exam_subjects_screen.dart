import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_navigation.dart';
import '../../../core/firebase/analytics_service.dart';
import '../../../core/testing/test_keys.dart';
import '../../../data/models/subject_model.dart';
import '../../../data/models/subject_progress_model.dart';
import '../../../data/models/user_exam_model.dart';
import '../../../data/repositories/dashboard_repository.dart';
import '../../widgets/sync_refresh_button.dart';

/// Subjects for a single enrolled exam (opened from Dashboard exam card).
class ExamSubjectsScreen extends StatefulWidget {
  const ExamSubjectsScreen({super.key, required this.userExamId});

  final int userExamId;

  @override
  State<ExamSubjectsScreen> createState() => _ExamSubjectsScreenState();
}

class _ExamSubjectsScreenState extends State<ExamSubjectsScreen> {
  final _repo = GetIt.I<DashboardRepository>();
  UserExamModel? _exam;
  List<SubjectModel> _subjects = const [];
  Map<int, SubjectProgressModel> _progressBySubject = const {};
  double _examProgress = 0;
  bool _loading = true;
  String? _error;

  static const Color _accent = Color(0xFF6C63FF);

  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView(screenName: 'ExamSubjectsScreen');
    _loadFromLocal();
  }

  Future<void> _loadFromLocal() async {
    final group =
        await _repo.buildSubjectGroupForUserExam(widget.userExamId);
    if (!mounted) return;

    if (group == null) {
      setState(() {
        _loading = false;
        _error =
            'No subjects cached for this exam. Tap SYNC while online.';
      });
      return;
    }

    final progressBySubject = <int, SubjectProgressModel>{
      for (final row in group.progressRows) row.subjectId: row,
    };
    final totalTopics =
        group.progressRows.fold<int>(0, (acc, e) => acc + e.totalTopics);
    final completedTopics =
        group.progressRows.fold<int>(0, (acc, e) => acc + e.completedTopics);
    final progress =
        totalTopics == 0 ? 0.0 : (completedTopics * 100.0 / totalTopics);

    setState(() {
      _exam = group.exam;
      _subjects = group.subjects;
      _progressBySubject = progressBySubject;
      _examProgress = progress;
      _loading = false;
      _error = null;
    });
  }

  Future<void> _openSubject(SubjectModel subject) async {
    final exam = _exam;
    if (exam == null) return;
    if (!exam.isActive) {
      await _repo.setActiveMyExam(exam.id);
    }
    if (!mounted) return;
    await AppNavigation.pushIfDifferent(
      context,
      '/subjects/exam/${widget.userExamId}/${subject.id}',
    );
    if (!mounted) return;
    await _loadFromLocal();
  }

  @override
  Widget build(BuildContext context) {
    final exam = _exam;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        AppNavigation.handleNestedBack(context, '/home');
      },
      child: Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        title: Text(exam?.examName ?? 'Subjects'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => AppNavigation.popOrGoIfDifferent(context, '/home'),
        ),
        actions: [
          SyncRefreshButton(onRefreshed: _loadFromLocal),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadFromLocal,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    children: [
                      _buildExamHeader(exam!),
                      const SizedBox(height: 14),
                      ..._subjects.map(_buildSubjectRow),
                    ],
                  ),
                ),
    ),
    );
  }

  Widget _buildExamHeader(UserExamModel exam) {
    final progress = (_examProgress / 100).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(18),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.description_outlined, color: _accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exam.examName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (exam.examDate != null)
                      Text(
                        exam.examDate!,
                        style: const TextStyle(
                          color: Color(0xFF7A7F8F),
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                '${_examProgress.toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: _accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: progress,
              color: _accent,
              backgroundColor: const Color(0xFFEDEEF7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_subjects.length} subjects · ${exam.daysLeft ?? 0} days left',
            style: const TextStyle(
              color: Color(0xFF7A7F8F),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectRow(SubjectModel subject) {
    final progress = _progressBySubject[subject.id];
    final completion = progress?.completionPercent ?? 0.0;
    final completedTopics = progress?.completedTopics ?? 0;
    final totalTopics = progress?.totalTopics ?? subject.topicCount;

    return Container(
      key: TestKeys.subjectRow(subject.id),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7F2)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openSubject(subject),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.menu_book_outlined,
                    size: 18, color: _accent),
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
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _accent,
                ),
              ),
              const SizedBox(width: 10),
              Text('$completedTopics/$totalTopics'),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
