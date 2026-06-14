import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_navigation.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/firebase/analytics_service.dart';
import '../../../core/network/api_error_message.dart';
import '../../../data/models/exam_category_model.dart';
import '../../../data/models/exam_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/dashboard_repository.dart';
import '../../../data/repositories/exam_catalog_repository.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/dashboard/dashboard_bloc.dart';
import '../../widgets/common/optional_subject_selection_dialog.dart';
import 'widgets/onboarding_shared_widgets.dart';

/// Add another exam from My Exams (non-onboarding) — local 3-step flow.
class AddExamWizardScreen extends StatefulWidget {
  const AddExamWizardScreen({super.key});

  @override
  State<AddExamWizardScreen> createState() => _AddExamWizardScreenState();
}

class _AddExamWizardScreenState extends State<AddExamWizardScreen> {
  final _catalogRepo = GetIt.I<ExamCatalogRepository>();
  final _dashboardRepo = GetIt.I<DashboardRepository>();
  final _searchCtrl = TextEditingController();

  int _step = 0;
  bool _catalogBaseLoading = false;
  bool _submitting = false;
  bool _examSelectionInProgress = false;
  String? _error;
  List<ExamCategoryModel> _categories = [];
  List<ExamModel> _featured = [];
  List<ExamModel> _recommended = [];
  final Map<int, List<ExamModel>> _categoryExams = {};
  final Set<int> _loadingCategoryIds = {};
  List<ExamModel> _searchResults = [];
  bool _searching = false;
  Set<int> _enrolledExamIds = {};

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
      _catalogBaseLoading = true;
      _error = null;
      _categories = [];
      _featured = [];
      _recommended = [];
      _categoryExams.clear();
      _loadingCategoryIds.clear();
    });
    try {
      final cached = await _catalogRepo.getCatalogCached();
      final catalogFuture =
          _catalogRepo.getCatalog(forceRemote: cached == null);
      final enrolledFuture = _dashboardRepo.getEnrolledExamIds();
      final catalog = await catalogFuture;
      final enrolledIds = await enrolledFuture;
      if (!mounted) return;

      setState(() {
        _enrolledExamIds = enrolledIds;
        _categories = catalog.categories;
        _featured = _dashboardRepo.excludeEnrolledExams(
          catalog.featuredExams,
          enrolledIds,
        );
        _recommended = _dashboardRepo.excludeEnrolledExams(
          catalog.recommendedExams,
          enrolledIds,
        );
        _catalogBaseLoading = false;
        _loadingCategoryIds
          ..clear()
          ..addAll(catalog.categories.map((cat) => cat.id));
      });

      for (final cat in catalog.categories) {
        unawaited(_loadCategoryExams(cat, enrolledIds));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _catalogBaseLoading = false;
        _loadingCategoryIds.clear();
        _error = e.toString();
      });
    }
  }

  Future<void> _loadCategoryExams(
    ExamCategoryModel cat,
    Set<int> enrolledIds,
  ) async {
    if (!mounted) return;
    setState(() => _loadingCategoryIds.add(cat.id));
    try {
      final exams = await _catalogRepo.getExamsByCategory(cat.id);
      if (!mounted) return;
      setState(() {
        _categoryExams[cat.id] =
            _dashboardRepo.excludeEnrolledExams(exams, enrolledIds);
        _loadingCategoryIds.remove(cat.id);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _categoryExams[cat.id] = const [];
        _loadingCategoryIds.remove(cat.id);
      });
    }
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
        _searchResults =
            _dashboardRepo.excludeEnrolledExams(results, _enrolledExamIds);
        _searching = false;
      });
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _selectExam(ExamModel exam) async {
    if (_examSelectionInProgress) return;
    if (_enrolledExamIds.contains(exam.id) ||
        await _dashboardRepo.isExamAlreadyEnrolled(exam.id)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are already enrolled in this exam'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    setState(() {
      _examSelectionInProgress = true;
      _selectedExam = exam;
      _step = 1;
    });

    try {
      final groups = await _dashboardRepo.getExamSubjectGroups(exam.id);
      final selections = await showOptionalSubjectSelectionDialog(
        context: context,
        examName: exam.name,
        groups: groups,
      );
      if (selections == null) {
        setState(() {
          _step = 0;
          _examSelectionInProgress = false;
          _selectedExam = null;
        });
        return;
      }
      setState(() {
        _selectedExam = exam;
        _subjectSelections = selections;
        _examSelectionInProgress = false;
      });
    } catch (e) {
      setState(() {
        _step = 0;
        _examSelectionInProgress = false;
        _selectedExam = null;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(apiErrorMessage(e)),
          backgroundColor: AppColors.error,
        ),
      );
    }
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
    if (await _dashboardRepo.isExamAlreadyEnrolled(_selectedExam!.id)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are already enrolled in this exam'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final examDate = _resolveExamDate();
      final user = await _catalogRepo.enrollExam(
        examId: _selectedExam!.id,
        examDate: examDate,
        syllabusTargetDate: examDate.subtract(const Duration(days: 30)),
        experienceLevel: _experience,
        subjectSelections: _subjectSelections,
      );
      final cachedUser = await _dashboardRepo.applyEnrollmentToCache(user);
      await GetIt.I<AuthRepository>().cacheUser(cachedUser);
      if (!mounted) return;
      AnalyticsService.logExamSelected(
        examId: _selectedExam!.id,
        examName: _selectedExam!.name,
      );
      context.read<AuthBloc>().add(AuthUserUpdated(user: cachedUser));
      context.read<DashboardBloc>().add(DashboardResetRequested());
      AppNavigation.replaceTo(
        context,
        '/offline-setup?mode=enrollment&redirect=${Uri.encodeComponent('/my-exams')}&title=${Uri.encodeComponent('Downloading Exam Content')}',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(apiErrorMessage(e)),
          backgroundColor: AppColors.error,
        ),
      );
    }
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
            } else if (context.canPop()) {
              AppNavigation.pop(context);
            }
          },
        ),
      ),
      body: _error != null && _step == 0 && _categories.isEmpty
          ? OnboardingErrorView(message: _error!, onRetry: _loadCatalog)
          : _buildStep(),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        if (_examSelectionInProgress) {
          return const Center(child: CircularProgressIndicator());
        }
        return OnboardingExamCatalogSection(
          searchCtrl: _searchCtrl,
          searching: _searching,
          searchResults: _searchResults,
          featured: _featured,
          recommended: _recommended,
          categories: _categories,
          categoryExams: _categoryExams,
          selectedId: _selectedExam?.id,
          onSelect: _selectExam,
          catalogBaseLoading: _catalogBaseLoading,
          loadingCategoryIds: _loadingCategoryIds,
        );
      case 1:
        return OnboardingGoalForm(
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
        return OnboardingConfirmSection(
          exam: _selectedExam!,
          examDate: _resolveExamDate(),
          experience: _experience,
          loading: _submitting,
          onConfirm: _confirmEnroll,
        );
    }
  }
}
