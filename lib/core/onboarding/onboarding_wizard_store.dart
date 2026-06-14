import 'package:flutter/foundation.dart';

import '../../data/models/exam_category_model.dart';
import '../../data/models/exam_model.dart';

/// Persists onboarding selections across separate route screens.
class OnboardingWizardStore extends ChangeNotifier {
  int? _userId;

  ExamModel? selectedExam;
  List<Map<String, dynamic>> subjectSelections = const [];
  bool selectionInProgress = false;

  String datePreset = 'upcoming';
  DateTime? customExamDate;
  String experience = 'BEGINNER';

  bool catalogLoaded = false;
  bool catalogLoading = false;
  String? catalogError;
  List<ExamCategoryModel> categories = const [];
  List<ExamModel> featured = const [];
  List<ExamModel> recommended = const [];
  Map<int, List<ExamModel>> categoryExams = const {};

  bool get hasCatalogBase =>
      categories.isNotEmpty || featured.isNotEmpty || recommended.isNotEmpty;

  bool get hasSelectableExams =>
      featured.isNotEmpty ||
      recommended.isNotEmpty ||
      categoryExams.values.any((exams) => exams.isNotEmpty);

  void bindUser(int userId) {
    if (_userId != userId) {
      reset();
      _userId = userId;
    }
  }

  void reset() {
    selectedExam = null;
    subjectSelections = const [];
    selectionInProgress = false;
    datePreset = 'upcoming';
    customExamDate = null;
    experience = 'BEGINNER';
    catalogLoaded = false;
    catalogLoading = false;
    catalogError = null;
    categories = const [];
    featured = const [];
    recommended = const [];
    categoryExams = const {};
    notifyListeners();
  }

  void setCatalogLoading() {
    catalogLoading = true;
    catalogError = null;
    notifyListeners();
  }

  void setCatalogError(String message) {
    catalogLoading = false;
    catalogError = message;
    notifyListeners();
  }

  void setCatalogBase({
    required List<ExamCategoryModel> categories,
    required List<ExamModel> featured,
    required List<ExamModel> recommended,
  }) {
    this.categories = categories;
    this.featured = featured;
    this.recommended = recommended;
    catalogLoading = true;
    catalogLoaded = false;
    catalogError = null;
    notifyListeners();
  }

  void setCategoryExams(int categoryId, List<ExamModel> exams) {
    categoryExams = {...categoryExams, categoryId: exams};
    notifyListeners();
  }

  void markCatalogComplete() {
    catalogLoaded = true;
    catalogLoading = false;
    catalogError = null;
    notifyListeners();
  }

  void cacheCatalog({
    required List<ExamCategoryModel> categories,
    required List<ExamModel> featured,
    required List<ExamModel> recommended,
    required Map<int, List<ExamModel>> categoryExams,
  }) {
    this.categories = categories;
    this.featured = featured;
    this.recommended = recommended;
    this.categoryExams = categoryExams;
    catalogLoaded = true;
    catalogLoading = false;
    catalogError = null;
    notifyListeners();
  }

  void beginExamSelection(ExamModel exam) {
    if (selectionInProgress) return;
    selectedExam = exam;
    selectionInProgress = true;
    notifyListeners();
  }

  void completeExamSelection(
    ExamModel exam,
    List<Map<String, dynamic>> selections,
  ) {
    selectedExam = exam;
    subjectSelections = selections;
    selectionInProgress = false;
    notifyListeners();
  }

  void cancelExamSelection() {
    selectedExam = null;
    subjectSelections = const [];
    selectionInProgress = false;
    notifyListeners();
  }

  void updateGoal({
    String? datePreset,
    DateTime? customExamDate,
    String? experience,
  }) {
    if (datePreset != null) this.datePreset = datePreset;
    if (customExamDate != null) this.customExamDate = customExamDate;
    if (experience != null) this.experience = experience;
    notifyListeners();
  }

  DateTime resolveExamDate() {
    final now = DateTime.now();
    switch (datePreset) {
      case 'next_year':
        return DateTime(now.year + 1, now.month, now.day);
      case 'custom':
        return customExamDate ?? now.add(const Duration(days: 90));
      default:
        return now.add(const Duration(days: 90));
    }
  }
}
