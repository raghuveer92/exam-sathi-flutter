import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/firebase/analytics_service.dart';
import '../../../data/models/exam_category_model.dart';
import '../../../data/models/exam_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/dashboard_repository.dart';
import '../../../data/repositories/exam_catalog_repository.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/dashboard/dashboard_bloc.dart';
import '../../widgets/common/gradient_button.dart';
import '../../widgets/common/optional_subject_selection_dialog.dart';

const double _kExamCardRowHeight = 172;

class AddExamWizardScreen extends StatefulWidget {
  final bool isOnboarding;

  const AddExamWizardScreen({super.key, this.isOnboarding = false});

  @override
  State<AddExamWizardScreen> createState() => _AddExamWizardScreenState();
}

class _AddExamWizardScreenState extends State<AddExamWizardScreen> {
  final _catalogRepo = GetIt.I<ExamCatalogRepository>();
  final _dashboardRepo = GetIt.I<DashboardRepository>();
  final _searchCtrl = TextEditingController();

  int _step = 0;
  bool _loading = true;
  String? _error;
  List<ExamCategoryModel> _categories = [];
  List<ExamModel> _featured = [];
  List<ExamModel> _recommended = [];
  final Map<int, List<ExamModel>> _categoryExams = {};
  List<ExamModel> _searchResults = [];
  bool _searching = false;

  ExamModel? _selectedExam;
  List<Map<String, dynamic>> _subjectSelections = [];

  DateTime? _examDate;
  String _datePreset = 'upcoming';
  String _experience = 'BEGINNER';

  @override
  void initState() {
    super.initState();
    _loadCatalog();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cached = await _catalogRepo.getCatalogCached();
      if (cached != null && mounted) {
        setState(() {
          _categories = cached.categories;
          _featured = cached.featuredExams;
          _recommended = cached.recommendedExams;
          _loading = false;
        });
      }
      final catalog = await _catalogRepo.getCatalog(forceRemote: cached == null);
      if (!mounted) return;
      setState(() {
        _categories = catalog.categories;
        _featured = catalog.featuredExams;
        _recommended = catalog.recommendedExams;
        _loading = false;
      });
      for (final cat in _categories) {
        _loadCategoryExams(cat.id);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadCategoryExams(int categoryId) async {
    try {
      final exams = await _catalogRepo.getExamsByCategory(categoryId);
      if (!mounted) return;
      setState(() => _categoryExams[categoryId] = exams);
    } catch (_) {}
  }

  void _onSearchChanged() {
    final q = _searchCtrl.text.trim();
    if (q.length < 2) {
      setState(() {
        _searching = false;
        _searchResults = [];
      });
      return;
    }
    _runSearch(q);
  }

  Future<void> _runSearch(String q) async {
    setState(() => _searching = true);
    try {
      final results = await _catalogRepo.searchExams(q);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _searching = false;
      });
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _selectExam(ExamModel exam) async {
    final groups = await _dashboardRepo.getExamSubjectGroups(exam.id);
    if (!mounted) return;
    final selections = await showOptionalSubjectSelectionDialog(
      context: context,
      examName: exam.name,
      groups: groups,
    );
    if (selections == null || !mounted) return;
    setState(() {
      _selectedExam = exam;
      _subjectSelections = selections;
      _step = 1;
    });
  }

  DateTime _resolveExamDate() {
    final now = DateTime.now();
    switch (_datePreset) {
      case 'next_year':
        return DateTime(now.year + 1, now.month, now.day);
      case 'custom':
        return _examDate ?? now.add(const Duration(days: 90));
      default:
        return now.add(const Duration(days: 90));
    }
  }

  Future<void> _confirmEnroll() async {
    if (_selectedExam == null) return;
    setState(() => _loading = true);
    try {
      final examDate = _resolveExamDate();
      final user = await _catalogRepo.enrollExam(
        examId: _selectedExam!.id,
        examDate: examDate,
        syllabusTargetDate: examDate.subtract(const Duration(days: 30)),
        experienceLevel: _experience,
        subjectSelections: _subjectSelections,
      );
      await GetIt.I<AuthRepository>().cacheUser(user);
      await _dashboardRepo.applyEnrollmentToCache(user);
      if (!mounted) return;
      AnalyticsService.logExamSelected(
        examId: _selectedExam!.id,
        examName: _selectedExam!.name,
      );
      context.read<AuthBloc>().add(AuthUserUpdated(user: user));
      context.read<DashboardBloc>().add(DashboardResetRequested());
      final redirect = widget.isOnboarding ? '/home' : '/my-exams';
      context.go(
        '/offline-setup?redirect=${Uri.encodeComponent(redirect)}&title=${Uri.encodeComponent('Downloading Exam Content')}',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_stepTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_step > 0) {
              setState(() => _step--);
            } else {
              context.pop();
            }
          },
        ),
      ),
      body: Column(
        children: [
          _WizardProgress(current: _step),
          Expanded(
            child: _loading && _step == 0
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _step == 0
                    ? _ErrorView(message: _error!, onRetry: _loadCatalog)
                    : _buildStep(),
          ),
        ],
      ),
    );
  }

  String get _stepTitle {
    switch (_step) {
      case 0:
        return 'Choose Your Exam';
      case 1:
        return 'Set Your Goal';
      default:
        return 'Confirm Setup';
    }
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _StepChooseExam(
          searchCtrl: _searchCtrl,
          searching: _searching,
          searchResults: _searchResults,
          featured: _featured,
          recommended: _recommended,
          categories: _categories,
          categoryExams: _categoryExams,
          selectedId: _selectedExam?.id,
          onSelect: _selectExam,
        );
      case 1:
        return _StepSetGoal(
          datePreset: _datePreset,
          examDate: _examDate,
          experience: _experience,
          onDatePreset: (v) => setState(() => _datePreset = v),
          onCustomDate: (d) => setState(() {
            _examDate = d;
            _datePreset = 'custom';
          }),
          onExperience: (e) => setState(() => _experience = e),
          onContinue: () => setState(() => _step = 2),
        );
      default:
        return _StepConfirm(
          exam: _selectedExam!,
          examDate: _resolveExamDate(),
          experience: _experience,
          loading: _loading,
          onConfirm: _confirmEnroll,
        );
    }
  }
}

class _WizardProgress extends StatelessWidget {
  final int current;
  const _WizardProgress({required this.current});

  static const _labels = ['Choose Exam', 'Set Goal', 'Confirm'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 340;
          return Row(
            children: [
              for (int i = 0; i < 3; i++) ...[
                if (i > 0)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: EdgeInsets.only(bottom: compact ? 0 : 14),
                      color: i <= current
                          ? AppColors.primary
                          : const Color(0xFFE8EAF0),
                    ),
                  ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: compact ? 12 : 14,
                        backgroundColor: i <= current
                            ? AppColors.primary
                            : const Color(0xFFE8EAF0),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            color: i <= current ? Colors.white : AppColors.textHint,
                            fontWeight: FontWeight.w700,
                            fontSize: compact ? 11 : 12,
                          ),
                        ),
                      ),
                      if (!compact) ...[
                        const SizedBox(height: 6),
                        Text(
                          _labels[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight:
                                i == current ? FontWeight.w700 : FontWeight.w500,
                            color: i <= current
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _StepChooseExam extends StatelessWidget {
  final TextEditingController searchCtrl;
  final bool searching;
  final List<ExamModel> searchResults;
  final List<ExamModel> featured;
  final List<ExamModel> recommended;
  final List<ExamCategoryModel> categories;
  final Map<int, List<ExamModel>> categoryExams;
  final int? selectedId;
  final ValueChanged<ExamModel> onSelect;

  const _StepChooseExam({
    required this.searchCtrl,
    required this.searching,
    required this.searchResults,
    required this.featured,
    required this.recommended,
    required this.categories,
    required this.categoryExams,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final showSearch = searchCtrl.text.trim().length >= 2;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'One Step Closer to Success! 🚀',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose your exam and we\'ll create the perfect roadmap for you.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                      height: 1.4,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: searchCtrl,
          decoration: InputDecoration(
            hintText: 'Search exams...',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        if (showSearch) ...[
          const SizedBox(height: 16),
          if (searching)
            const Center(child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ))
          else if (searchResults.isEmpty)
            const Text('No exams found', style: TextStyle(color: AppColors.textSecondary))
          else
            ...searchResults.map((e) => _ExamListTile(
                  exam: e,
                  selected: e.id == selectedId,
                  onTap: () => onSelect(e),
                )),
        ] else ...[
          if (recommended.isNotEmpty) ...[
            _SectionHeader(title: 'Recommended for You', icon: Icons.star_outline),
            SizedBox(
              height: _kExamCardRowHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: recommended.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => _ExamCard(
                  exam: recommended[i],
                  selected: recommended[i].id == selectedId,
                  onTap: () => onSelect(recommended[i]),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
          if (featured.isNotEmpty) ...[
            _SectionHeader(title: 'Featured Exams', icon: Icons.local_fire_department_outlined),
            SizedBox(
              height: _kExamCardRowHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: featured.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => _ExamCard(
                  exam: featured[i],
                  selected: featured[i].id == selectedId,
                  onTap: () => onSelect(featured[i]),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
          for (final cat in categories) ...[
            _SectionHeader(
              title: cat.name,
              icon: _categoryIcon(cat.icon),
              trailing: Text('${cat.examCount} exams',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ),
            SizedBox(
              height: _kExamCardRowHeight,
              child: (categoryExams[cat.id] ?? []).isEmpty
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: categoryExams[cat.id]!.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (_, i) {
                        final exam = categoryExams[cat.id]![i];
                        return _ExamCard(
                          exam: exam,
                          selected: exam.id == selectedId,
                          onTap: () => onSelect(exam),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 20),
          ],
        ],
      ],
    );
  }

  IconData _categoryIcon(String? icon) {
    switch (icon) {
      case 'school':
        return Icons.school_outlined;
      case 'engineering':
        return Icons.precision_manufacturing_outlined;
      case 'medical_services':
        return Icons.medical_services_outlined;
      case 'account_balance':
        return Icons.account_balance_outlined;
      default:
        return Icons.category_outlined;
    }
  }
}

class _StepSetGoal extends StatelessWidget {
  final String datePreset;
  final DateTime? examDate;
  final String experience;
  final ValueChanged<String> onDatePreset;
  final ValueChanged<DateTime> onCustomDate;
  final ValueChanged<String> onExperience;
  final VoidCallback onContinue;

  const _StepSetGoal({
    required this.datePreset,
    required this.examDate,
    required this.experience,
    required this.onDatePreset,
    required this.onCustomDate,
    required this.onExperience,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        const Text('Target Exam Date',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _ChipOption(
              label: 'Upcoming Attempt',
              selected: datePreset == 'upcoming',
              onTap: () => onDatePreset('upcoming'),
            ),
            _ChipOption(
              label: 'Next Year',
              selected: datePreset == 'next_year',
              onTap: () => onDatePreset('next_year'),
            ),
            _ChipOption(
              label: examDate != null
                  ? '${examDate!.year}-${examDate!.month}-${examDate!.day}'
                  : 'Custom Date',
              selected: datePreset == 'custom',
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: examDate ?? DateTime.now().add(const Duration(days: 90)),
                  firstDate: DateTime.now().add(const Duration(days: 1)),
                  lastDate: DateTime.now().add(const Duration(days: 1500)),
                );
                if (picked != null) onCustomDate(picked);
              },
            ),
          ],
        ),
        const SizedBox(height: 28),
        const Text('Experience Level',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          children: [
            _ChipOption(
              label: 'Beginner',
              selected: experience == 'BEGINNER',
              onTap: () => onExperience('BEGINNER'),
            ),
            _ChipOption(
              label: 'Intermediate',
              selected: experience == 'INTERMEDIATE',
              onTap: () => onExperience('INTERMEDIATE'),
            ),
            _ChipOption(
              label: 'Advanced',
              selected: experience == 'ADVANCED',
              onTap: () => onExperience('ADVANCED'),
            ),
          ],
        ),
        const SizedBox(height: 32),
        GradientButton(label: 'Continue', onPressed: onContinue),
      ],
    );
  }
}

class _StepConfirm extends StatelessWidget {
  final ExamModel exam;
  final DateTime examDate;
  final String experience;
  final bool loading;
  final VoidCallback onConfirm;

  const _StepConfirm({
    required this.exam,
    required this.examDate,
    required this.experience,
    required this.loading,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(exam.name,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(exam.cardSubtitle,
                    style: const TextStyle(color: AppColors.textSecondary)),
                const Divider(height: 28),
                _SummaryRow('Target Date', '${examDate.year}-${examDate.month}-${examDate.day}'),
                _SummaryRow('Experience', experience.toLowerCase()),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        GradientButton(
          label: 'Create My Study Plan',
          isLoading: loading,
          onPressed: onConfirm,
        ),
      ],
    );
  }
}

class _ExamCard extends StatelessWidget {
  final ExamModel exam;
  final bool selected;
  final VoidCallback onTap;

  const _ExamCard({
    required this.exam,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = _parseColor(exam.colorCode);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 148,
        height: _kExamCardRowHeight,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.primary : const Color(0xFFE8EAF0),
              width: selected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: color.withValues(alpha: 0.15),
                    child: Text(
                      exam.name.isNotEmpty ? exam.name[0] : '?',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  if (exam.popular) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Popular',
                        style: TextStyle(
                          color: AppColors.success,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                exam.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  exam.cardSubtitle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _parseColor(String? hex) {
    if (hex == null || hex.length < 7) return AppColors.primary;
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return AppColors.primary;
    }
  }
}

class _ExamListTile extends StatelessWidget {
  final ExamModel exam;
  final bool selected;
  final VoidCallback onTap;

  const _ExamListTile({
    required this.exam,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? AppColors.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: ListTile(
        title: Text(exam.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(exam.cardSubtitle),
        trailing: exam.popular
            ? const Chip(
                label: Text('Popular', style: TextStyle(fontSize: 10)),
                visualDensity: VisualDensity.compact,
              )
            : null,
        onTap: onTap,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget? trailing;

  const _SectionHeader({required this.title, required this.icon, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Flexible(child: trailing!),
          ],
        ],
      ),
    );
  }
}

class _ChipOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChipOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.1)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : const Color(0xFFD8DDEA),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.primary : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(color: AppColors.textSecondary))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
