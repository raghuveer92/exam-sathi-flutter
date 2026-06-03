import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/exam_subject_group_model.dart';
import '../../../data/models/exam_model.dart';
import '../../../data/models/user_exam_model.dart';
import '../../../data/repositories/dashboard_repository.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/dashboard/dashboard_bloc.dart';
import '../../widgets/common/gradient_button.dart';
import '../../widgets/common/optional_subject_selection_dialog.dart';

class MyExamsScreen extends StatefulWidget {
  final bool isOnboarding;

  const MyExamsScreen({super.key, this.isOnboarding = false});

  @override
  State<MyExamsScreen> createState() => _MyExamsScreenState();
}

class _MyExamsScreenState extends State<MyExamsScreen> {
  final _repo = GetIt.I<DashboardRepository>();
  bool _loading = true;
  List<UserExamModel> _myExams = const [];
  List<ExamModel> _allExams = const [];

  DateTime _offsetFromToday({required int months}) {
    final now = DateTime.now();
    return DateTime(now.year, now.month + months, now.day);
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  InputDecoration _dialogFieldDecoration({
    required String hintText,
    Widget? prefixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(
        color: AppColors.textHint,
        fontWeight: FontWeight.w500,
      ),
      prefixIcon: prefixIcon,
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFD8DDEA)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }

  Widget _buildQuickOption({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary.withValues(alpha: 0.08) : AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? AppColors.primary : const Color(0xFFD8DDEA),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 20,
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected ? AppColors.primary : AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 10),
                Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, size: 14, color: Colors.white),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _repo.getMyExams(),
        _repo.getExams(),
      ]);
      if (!mounted) return;
      setState(() {
        _myExams = results[0] as List<UserExamModel>;
        _allExams = results[1] as List<ExamModel>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _syncUserInState() async {
    final me = await GetIt.I<DashboardRepository>().getDashboard();
    if (!mounted) return;
    context.read<DashboardBloc>().add(DashboardRefreshRequested());
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      context.read<AuthBloc>().add(AuthUserUpdated(user: me.user));
    }
  }

  Future<void> _continueOnboarding() async {
    await _syncUserInState();
    if (!mounted) return;
    context.go('/exam-goal');
  }

  Future<void> _addExam() async {
    final existingExamIds = _myExams.map((e) => e.examId).toSet();
    final available = _allExams.where((e) => !existingExamIds.contains(e.id)).toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All available exams are already added.')),
      );
      return;
    }

    ExamModel? selected;
    DateTime? targetDate;

    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 40,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 28, 28, 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Add Exam',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context, false),
                            icon: const Icon(Icons.close_rounded, size: 28),
                            color: AppColors.textSecondary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Exam Name',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Autocomplete<ExamModel>(
                        displayStringForOption: (exam) => exam.name,
                        optionsBuilder: (textEditingValue) {
                          final query = textEditingValue.text.trim().toLowerCase();
                          if (query.isEmpty) return available;
                          return available.where(
                            (exam) => exam.name.toLowerCase().contains(query),
                          );
                        },
                        onSelected: (exam) => setLocal(() => selected = exam),
                        fieldViewBuilder: (
                          context,
                          textEditingController,
                          focusNode,
                          onFieldSubmitted,
                        ) {
                          return TextFormField(
                            controller: textEditingController,
                            focusNode: focusNode,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: _dialogFieldDecoration(
                              hintText: 'Enter exam name',
                            ),
                            onChanged: (value) {
                              if (selected != null && value.trim() != selected!.name) {
                                setLocal(() => selected = null);
                              }
                            },
                          );
                        },
                        optionsViewBuilder: (context, onSelected, options) {
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              color: AppColors.surface,
                              elevation: 8,
                              borderRadius: BorderRadius.circular(16),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 260, minWidth: 320),
                                child: ListView.builder(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  shrinkWrap: true,
                                  itemCount: options.length,
                                  itemBuilder: (context, index) {
                                    final exam = options.elementAt(index);
                                    return ListTile(
                                      title: Text(
                                        exam.name,
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                      onTap: () => onSelected(exam),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 28),
                      const Text(
                        'Target Date',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: targetDate ?? DateTime.now().add(const Duration(days: 90)),
                            firstDate: DateTime.now().add(const Duration(days: 1)),
                            lastDate: DateTime.now().add(const Duration(days: 1500)),
                          );
                          if (picked != null) setLocal(() => targetDate = picked);
                        },
                        child: InputDecorator(
                          decoration: _dialogFieldDecoration(
                            hintText: 'Select target date',
                            prefixIcon: const Padding(
                              padding: EdgeInsets.only(left: 18, right: 8),
                              child: Icon(
                                Icons.calendar_today_outlined,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          child: Text(
                            targetDate == null ? 'Select target date' : _formatDate(targetDate!),
                            style: TextStyle(
                              color: targetDate == null ? AppColors.textHint : AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Row(
                        children: [
                          Expanded(child: Divider(color: Color(0xFFD8DDEA), thickness: 1)),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 18),
                            child: Text(
                              'or',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(child: Divider(color: Color(0xFFD8DDEA), thickness: 1)),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Quick Options',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _buildQuickOption(
                            label: '3 Months',
                            isSelected: targetDate != null &&
                                _formatDate(targetDate!) == _formatDate(_offsetFromToday(months: 3)),
                            onTap: () => setLocal(() => targetDate = _offsetFromToday(months: 3)),
                          ),
                          const SizedBox(width: 12),
                          _buildQuickOption(
                            label: '6 Months',
                            isSelected: targetDate != null &&
                                _formatDate(targetDate!) == _formatDate(_offsetFromToday(months: 6)),
                            onTap: () => setLocal(() => targetDate = _offsetFromToday(months: 6)),
                          ),
                          const SizedBox(width: 12),
                          _buildQuickOption(
                            label: '1 Year',
                            isSelected: targetDate != null &&
                                _formatDate(targetDate!) == _formatDate(_offsetFromToday(months: 12)),
                            onTap: () => setLocal(() => targetDate = _offsetFromToday(months: 12)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      GradientButton(
                        label: 'Add Exam',
                        onPressed: selected != null && targetDate != null
                            ? () => Navigator.pop(context, true)
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    if (ok != true || selected == null) return;
    final groups = await _repo.getExamSubjectGroups(selected!.id);
    final selections = await _collectSelections(selected!.name, groups);
    if (selections == null) return;

    await _repo.addMyExam(
      examId: selected!.id,
      examDate: targetDate,
      subjectSelections: selections,
    );
    await _load();
    await _syncUserInState();
  }

  Future<List<Map<String, dynamic>>?> _collectSelections(
    String examName,
    List<ExamSubjectGroupModel> groups,
  ) {
    return showOptionalSubjectSelectionDialog(
      context: context,
      examName: examName,
      groups: groups,
    );
  }

  Future<void> _editDate(UserExamModel ue) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(ue.examDate ?? '') ?? DateTime.now().add(const Duration(days: 90)),
      firstDate: DateTime.now().add(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 1500)),
    );
    if (picked == null) return;
    await _repo.updateMyExamDate(ue.id, picked);
    await _load();
    await _syncUserInState();
  }

  Future<void> _delete(UserExamModel ue) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove exam?'),
        content: Text('Do you want to remove ${ue.examName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      // If user is deleting the active exam and others exist,
      // switch active exam first to keep backend state valid.
      if (ue.isActive && _myExams.length > 1) {
        final fallback = _myExams.firstWhere((x) => x.id != ue.id);
        await _repo.setActiveMyExam(fallback.id);
      }

      await _repo.deleteMyExam(ue.id);
      await _load();
      await _syncUserInState();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exam removed successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete exam: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Exams')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addExam,
        label: const Text('Add Exam'),
        icon: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: _myExams.length,
                itemBuilder: (_, i) {
                  final e = _myExams[i];
                  final p = (e.progressPercent ?? 0).clamp(0, 100) / 100.0;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  e.examName,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                                ),
                              ),
                              if (e.isActive)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text('Active', style: TextStyle(color: AppColors.success)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text('Syllabus target: ${e.examDate ?? 'Not set'}'),
                          Text('Days left to target: ${e.daysLeft?.toString() ?? '--'}'),
                          Text('Subjects: ${e.totalSubjects?.toString() ?? '--'}'),
                          Text('Progress: ${(e.progressPercent ?? 0).toStringAsFixed(1)}%'),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(value: p.isNaN ? 0 : p),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: () => _editDate(e),
                                icon: const Icon(Icons.edit_calendar_outlined),
                                label: const Text('Edit Target'),
                              ),
                              const Spacer(),
                              if (!e.isActive)
                                TextButton(
                                  onPressed: () async {
                                    await _repo.setActiveMyExam(e.id);
                                    await _load();
                                    await _syncUserInState();
                                  },
                                  child: const Text('Make Active'),
                                ),
                              IconButton(
                                onPressed: _myExams.length <= 1 ? null : () => _delete(e),
                                icon: const Icon(Icons.delete_outline),
                                color: AppColors.error,
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
      bottomNavigationBar: widget.isOnboarding
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: ElevatedButton(
                onPressed: _myExams.isEmpty ? null : _continueOnboarding,
                child: Text(_myExams.isEmpty
                    ? 'Add at least one exam to continue'
                    : 'Continue to Goal Setup'),
              ),
            )
          : null,
    );
  }
}
