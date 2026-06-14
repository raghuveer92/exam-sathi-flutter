import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/onboarding/onboarding_wizard_store.dart';
import '../../../core/router/app_navigation.dart';
import '../../../core/testing/test_keys.dart';
import '../../../data/models/exam_category_model.dart';
import '../../../data/models/exam_model.dart';
import '../../../data/models/exam_subject_group_model.dart';
import '../../../data/repositories/exam_catalog_repository.dart';
import '../../../data/repositories/dashboard_repository.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../widgets/common/optional_subject_selection_dialog.dart';
import 'widgets/onboarding_shared_widgets.dart';

const _isIntegrationTest = bool.fromEnvironment('INTEGRATION_TEST');

/// Screen 1 — choose exam (onboarding).
class OnboardingChooseExamScreen extends StatefulWidget {
  const OnboardingChooseExamScreen({super.key});

  @override
  State<OnboardingChooseExamScreen> createState() =>
      _OnboardingChooseExamScreenState();
}

class _OnboardingChooseExamScreenState extends State<OnboardingChooseExamScreen> {
  final _catalogRepo = GetIt.I<ExamCatalogRepository>();
  late final OnboardingWizardStore _store;
  final _searchCtrl = TextEditingController();

  bool _catalogBaseLoading = false;
  String? _error;
  List<ExamCategoryModel> _categories = [];
  List<ExamModel> _featured = [];
  List<ExamModel> _recommended = [];
  final Map<int, List<ExamModel>> _categoryExams = {};
  final Set<int> _loadingCategoryIds = {};
  List<ExamModel> _searchResults = [];
  bool _searching = false;

  bool get _hasSelectableExams =>
      _featured.isNotEmpty ||
      _recommended.isNotEmpty ||
      _categoryExams.values.any((exams) => exams.isNotEmpty);

  bool get _catalogReady =>
      _error == null &&
      !_catalogBaseLoading &&
      (_hasSelectableExams || _loadingCategoryIds.isEmpty);

  @override
  void initState() {
    super.initState();
    _store = GetIt.I<OnboardingWizardStore>();
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      _store.bindUser(authState.user.id);
    }
    _store.addListener(_onStoreChanged);
    _hydrateFromStore();
    if (!_store.catalogLoaded) {
      unawaited(_loadCatalog());
    } else {
      _resumeCategoryLoadsIfNeeded();
    }
    _searchCtrl.addListener(_onSearchChanged);
  }

  void _onStoreChanged() {
    if (!mounted) return;
    setState(_hydrateFromStore);
  }

  void _hydrateFromStore() {
    if (!_store.hasCatalogBase && !_store.catalogLoaded) return;
    _categories = List<ExamCategoryModel>.from(_store.categories);
    _featured = List<ExamModel>.from(_store.featured);
    _recommended = List<ExamModel>.from(_store.recommended);
    _categoryExams
      ..clear()
      ..addAll(_store.categoryExams);
    _catalogBaseLoading = _store.catalogLoading && !_store.catalogLoaded;
    _error = _store.catalogError;
    _loadingCategoryIds
      ..clear()
      ..addAll(
        _categories
            .map((cat) => cat.id)
            .where((id) => !_categoryExams.containsKey(id)),
      );
  }

  void _resumeCategoryLoadsIfNeeded() {
    for (final cat in _categories) {
      if (_categoryExams.containsKey(cat.id)) continue;
      _loadingCategoryIds.add(cat.id);
      unawaited(_loadCategoryExams(cat));
    }
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    _store.setCatalogLoading();
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
      final catalog =
          await _catalogRepo.getCatalog(forceRemote: cached == null);
      if (!mounted) return;

      _store.setCatalogBase(
        categories: catalog.categories,
        featured: catalog.featuredExams,
        recommended: catalog.recommendedExams,
      );

      setState(() {
        _categories = catalog.categories;
        _featured = catalog.featuredExams;
        _recommended = catalog.recommendedExams;
        _catalogBaseLoading = false;
        _loadingCategoryIds
          ..clear()
          ..addAll(catalog.categories.map((cat) => cat.id));
      });

      for (final cat in catalog.categories) {
        unawaited(_loadCategoryExams(cat));
      }
    } catch (e) {
      if (!mounted) return;
      _store.setCatalogError(e.toString());
      setState(() {
        _catalogBaseLoading = false;
        _loadingCategoryIds.clear();
        _error = e.toString();
      });
    }
  }

  Future<void> _loadCategoryExams(ExamCategoryModel cat) async {
    if (!mounted) return;
    setState(() => _loadingCategoryIds.add(cat.id));
    try {
      final exams = await _catalogRepo.getExamsByCategory(cat.id);
      if (!mounted) return;
      _store.setCategoryExams(cat.id, exams);
      setState(() {
        _categoryExams[cat.id] = exams;
        _loadingCategoryIds.remove(cat.id);
      });
      _maybeMarkCatalogComplete();
    } catch (_) {
      if (!mounted) return;
      _store.setCategoryExams(cat.id, const []);
      setState(() {
        _categoryExams[cat.id] = const [];
        _loadingCategoryIds.remove(cat.id);
      });
      _maybeMarkCatalogComplete();
    }
  }

  void _maybeMarkCatalogComplete() {
    if (_catalogBaseLoading || _loadingCategoryIds.isNotEmpty) return;
    _store.markCatalogComplete();
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

  void _selectExam(ExamModel exam) {
    if (_store.selectionInProgress) return;

    _store.beginExamSelection(exam);
    AppNavigation.pushIfDifferent(context, '/onboarding/set-goal');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final showFatalError =
            _error != null && !_store.hasCatalogBase && !_hasSelectableExams;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Choose Your Exam'),
            automaticallyImplyLeading: false,
          ),
          body: showFatalError
              ? OnboardingErrorView(message: _error!, onRetry: _loadCatalog)
              : Stack(
                  children: [
                    OnboardingExamCatalogSection(
                      searchCtrl: _searchCtrl,
                      searching: _searching,
                      searchResults: _searchResults,
                      featured: _featured,
                      recommended: _recommended,
                      categories: _categories,
                      categoryExams: _categoryExams,
                      selectedId: _store.selectedExam?.id,
                      onSelect: _selectExam,
                      catalogBaseLoading: _catalogBaseLoading,
                      loadingCategoryIds: _loadingCategoryIds,
                    ),
                    if (_catalogReady)
                      const SizedBox(
                        key: TestKeys.examCatalogReady,
                        width: 0,
                        height: 0,
                      ),
                  ],
                ),
        );
      },
    );
  }
}

/// Resolves optional subjects after exam pick — runs on the goal screen.
Future<void> completeOnboardingExamSelection({
  required BuildContext context,
  required OnboardingWizardStore store,
  required DashboardRepository dashboardRepo,
}) async {
  final exam = store.selectedExam;
  if (exam == null || !store.selectionInProgress) return;

  try {
    final groups = await dashboardRepo.getExamSubjectGroups(exam.id);
    if (!context.mounted) return;
    final selections = await _resolveSubjectSelections(context, exam, groups);

    if (selections == null) {
      store.cancelExamSelection();
      if (context.mounted) AppNavigation.pop(context);
      return;
    }

    store.completeExamSelection(exam, selections);
  } catch (e) {
    store.completeExamSelection(exam, const []);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
    );
  }
}

Future<List<Map<String, dynamic>>?> _resolveSubjectSelections(
  BuildContext context,
  ExamModel exam,
  List<ExamSubjectGroupModel> groups,
) async {
  final optionalGroups = groups.where((group) => group.isOptional).toList();
  if (optionalGroups.isEmpty) return const [];

  if (_isIntegrationTest) {
    return [
      for (final group in optionalGroups)
        {
          'groupId': group.id,
          'subjectIds': group.subjects
              .take(group.minSelection > 0 ? group.minSelection : 1)
              .map((subject) => subject.id)
              .toList(),
        },
    ];
  }

  if (!context.mounted) return null;
  return showOptionalSubjectSelectionDialog(
    context: context,
    examName: exam.name,
    groups: groups,
  );
}
