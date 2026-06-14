import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/testing/test_keys.dart';
import '../../../../data/models/exam_category_model.dart';
import '../../../../data/models/exam_model.dart';
import '../../../widgets/common/gradient_button.dart';

const double kOnboardingExamCardRowHeight = 156;
const double kOnboardingExamCardWidth = 168;

IconData examIconFromUrl(String? iconUrl) {
  switch (iconUrl) {
    case 'workspace_premium':
      return Icons.workspace_premium_outlined;
    case 'menu_book':
      return Icons.menu_book_outlined;
    case 'public':
      return Icons.public_outlined;
    case 'psychology':
      return Icons.psychology_outlined;
    case 'calculate':
      return Icons.calculate_outlined;
    case 'school':
      return Icons.school_outlined;
    case 'medical_services':
      return Icons.medical_services_outlined;
    case 'account_balance':
      return Icons.account_balance_outlined;
    case 'train':
      return Icons.train_outlined;
    case 'gavel':
      return Icons.gavel_outlined;
    case 'engineering':
      return Icons.precision_manufacturing_outlined;
    case 'shield':
      return Icons.shield_outlined;
    default:
      return Icons.assignment_outlined;
  }
}

Color _examAccentColor(String? hex) {
  if (hex == null || hex.length < 7) return AppColors.primary;
  try {
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  } catch (_) {
    return AppColors.primary;
  }
}

class OnboardingExamCatalogSection extends StatelessWidget {
  const OnboardingExamCatalogSection({
    super.key,
    required this.searchCtrl,
    required this.searching,
    required this.searchResults,
    required this.featured,
    required this.recommended,
    required this.categories,
    required this.categoryExams,
    required this.selectedId,
    required this.onSelect,
    this.catalogBaseLoading = false,
    this.loadingCategoryIds = const {},
  });

  final TextEditingController searchCtrl;
  final bool searching;
  final List<ExamModel> searchResults;
  final List<ExamModel> featured;
  final List<ExamModel> recommended;
  final List<ExamCategoryModel> categories;
  final Map<int, List<ExamModel>> categoryExams;
  final int? selectedId;
  final ValueChanged<ExamModel> onSelect;
  final bool catalogBaseLoading;
  final Set<int> loadingCategoryIds;

  @override
  Widget build(BuildContext context) {
    final showSearch = searchCtrl.text.trim().length >= 2;
    return ListView(
      key: const PageStorageKey<String>('onboarding_exam_catalog'),
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
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            )
          else if (searchResults.isEmpty)
            const Text('No exams found',
                style: TextStyle(color: AppColors.textSecondary))
          else
            ...searchResults.map(
              (e) => OnboardingExamListTile(
                exam: e,
                selected: e.id == selectedId,
                onTap: () => onSelect(e),
              ),
            ),
        ] else ...[
          if (catalogBaseLoading) ...[
            const OnboardingSectionHeader(title: 'Popular Exams'),
            const OnboardingExamRowSkeleton(),
            const SizedBox(height: 20),
            const OnboardingSectionHeader(title: 'Featured Exams'),
            const OnboardingExamRowSkeleton(),
            const SizedBox(height: 20),
          ] else ...[
            if (recommended.isNotEmpty)
              _ExamHorizontalSection(
                title: 'Popular Exams',
                exams: recommended,
                selectedId: selectedId,
                onSelect: onSelect,
              ),
            if (featured.isNotEmpty)
              _ExamHorizontalSection(
                title: 'Featured Exams',
                exams: featured,
                selectedId: selectedId,
                onSelect: onSelect,
              ),
          ],
          for (final cat in categories) ...[
            if (loadingCategoryIds.contains(cat.id) ||
                (categoryExams[cat.id] ?? const []).isNotEmpty) ...[
              if (loadingCategoryIds.contains(cat.id)) ...[
                OnboardingSectionHeader(title: cat.name),
                const OnboardingExamRowSkeleton(),
                const SizedBox(height: 20),
              ] else
                _ExamHorizontalSection(
                  title: cat.name,
                  exams: categoryExams[cat.id]!,
                  selectedId: selectedId,
                  onSelect: onSelect,
                ),
            ],
          ],
        ],
      ],
    );
  }
}

class _ExamHorizontalSection extends StatelessWidget {
  const _ExamHorizontalSection({
    required this.title,
    required this.exams,
    required this.selectedId,
    required this.onSelect,
  });

  final String title;
  final List<ExamModel> exams;
  final int? selectedId;
  final ValueChanged<ExamModel> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        OnboardingSectionHeader(
          title: title,
          onViewAll: exams.length > 3
              ? () => _showAllExamsSheet(
                    context,
                    title: title,
                    exams: exams,
                    selectedId: selectedId,
                    onSelect: onSelect,
                  )
              : null,
        ),
        SizedBox(
          height: kOnboardingExamCardRowHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: exams.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final exam = exams[i];
              return OnboardingExamCard(
                exam: exam,
                selected: exam.id == selectedId,
                onTap: () => onSelect(exam),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

void _showAllExamsSheet(
  BuildContext context, {
  required String title,
  required List<ExamModel> exams,
  required int? selectedId,
  required ValueChanged<ExamModel> onSelect,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.textHint.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.55,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: exams.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final exam = exams[i];
                    return OnboardingExamListTile(
                      exam: exam,
                      selected: exam.id == selectedId,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        onSelect(exam);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class OnboardingExamRowSkeleton extends StatelessWidget {
  const OnboardingExamRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.shimmerBase,
      highlightColor: AppColors.shimmerHighlight,
      period: const Duration(milliseconds: 1200),
      child: SizedBox(
        height: kOnboardingExamCardRowHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 3,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, __) => const _OnboardingExamCardSkeleton(),
        ),
      ),
    );
  }
}

class _OnboardingExamCardSkeleton extends StatelessWidget {
  const _OnboardingExamCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kOnboardingExamCardWidth,
      height: kOnboardingExamCardRowHeight,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EAF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.shimmerBase,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const Spacer(),
              Container(
                width: 52,
                height: 18,
                decoration: BoxDecoration(
                  color: AppColors.shimmerBase,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 15,
            width: 120,
            decoration: BoxDecoration(
              color: AppColors.shimmerBase,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 12,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.shimmerBase,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            height: 12,
            width: 100,
            decoration: BoxDecoration(
              color: AppColors.shimmerBase,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}

IconData onboardingCategoryIcon(String? icon) {
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

class OnboardingGoalForm extends StatelessWidget {
  const OnboardingGoalForm({
    super.key,
    required this.datePreset,
    required this.examDate,
    required this.experience,
    required this.onDatePreset,
    required this.onCustomDate,
    required this.onExperience,
    required this.onContinue,
  });

  final String datePreset;
  final DateTime? examDate;
  final String experience;
  final ValueChanged<String> onDatePreset;
  final ValueChanged<DateTime> onCustomDate;
  final ValueChanged<String> onExperience;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: TestKeys.onboardingGoalStep,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        const Text('Target Exam Date',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OnboardingChipOption(
              label: 'Upcoming Attempt',
              selected: datePreset == 'upcoming',
              onTap: () => onDatePreset('upcoming'),
            ),
            OnboardingChipOption(
              label: 'Next Year',
              selected: datePreset == 'next_year',
              onTap: () => onDatePreset('next_year'),
            ),
            OnboardingChipOption(
              label: examDate != null
                  ? '${examDate!.year}-${examDate!.month}-${examDate!.day}'
                  : 'Custom Date',
              selected: datePreset == 'custom',
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate:
                      examDate ?? DateTime.now().add(const Duration(days: 90)),
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
            OnboardingChipOption(
              label: 'Beginner',
              selected: experience == 'BEGINNER',
              onTap: () => onExperience('BEGINNER'),
            ),
            OnboardingChipOption(
              label: 'Intermediate',
              selected: experience == 'INTERMEDIATE',
              onTap: () => onExperience('INTERMEDIATE'),
            ),
            OnboardingChipOption(
              label: 'Advanced',
              selected: experience == 'ADVANCED',
              onTap: () => onExperience('ADVANCED'),
            ),
          ],
        ),
        const SizedBox(height: 32),
        GradientButton(
          label: 'Continue',
          buttonKey: TestKeys.onboardingGoalContinue,
          onPressed: onContinue,
        ),
      ],
    );
  }
}

class OnboardingConfirmSection extends StatelessWidget {
  const OnboardingConfirmSection({
    super.key,
    required this.exam,
    required this.examDate,
    required this.experience,
    required this.loading,
    required this.onConfirm,
  });

  final ExamModel exam;
  final DateTime examDate;
  final String experience;
  final bool loading;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: TestKeys.onboardingConfirmStep,
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exam.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  exam.cardSubtitle,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const Divider(height: 28),
                OnboardingSummaryRow(
                  'Target Date',
                  '${examDate.year}-${examDate.month}-${examDate.day}',
                ),
                OnboardingSummaryRow(
                  'Experience',
                  experience.toLowerCase(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        GradientButton(
          buttonKey: TestKeys.onboardingConfirmSubmit,
          label: 'Create My Study Plan',
          isLoading: loading,
          onPressed: onConfirm,
        ),
      ],
    );
  }
}

class OnboardingExamCard extends StatelessWidget {
  const OnboardingExamCard({
    super.key,
    required this.exam,
    required this.selected,
    required this.onTap,
  });

  final ExamModel exam;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = _examAccentColor(exam.colorCode);
    return Semantics(
      button: true,
      label: 'Select ${exam.name}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: TestKeys.examCard(exam.id),
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: kOnboardingExamCardWidth,
            height: kOnboardingExamCardRowHeight,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.05)
                    : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? AppColors.primary
                      : const Color(0xFFE8EAF0),
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          examIconFromUrl(exam.iconUrl),
                          size: 22,
                          color: accent,
                        ),
                      ),
                      const Spacer(),
                      if (exam.popular || exam.featured)
                        _ExamCardBadge(exam: exam),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    exam.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppColors.textPrimary,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    exam.cardSubtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExamCardBadge extends StatelessWidget {
  const _ExamCardBadge({required this.exam});

  final ExamModel exam;

  @override
  Widget build(BuildContext context) {
    final bool isPopular = exam.popular;
    final label = isPopular ? 'Popular' : 'Featured';
    final bg = isPopular
        ? AppColors.success.withValues(alpha: 0.12)
        : AppColors.primary.withValues(alpha: 0.12);
    final fg = isPopular ? AppColors.success : AppColors.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class OnboardingExamListTile extends StatelessWidget {
  const OnboardingExamListTile({
    super.key,
    required this.exam,
    required this.selected,
    required this.onTap,
  });

  final ExamModel exam;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = _examAccentColor(exam.colorCode);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.05)
                : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.primary : const Color(0xFFE8EAF0),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  examIconFromUrl(exam.iconUrl),
                  size: 22,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exam.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      exam.cardSubtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (exam.popular || exam.featured) ...[
                const SizedBox(width: 8),
                _ExamCardBadge(exam: exam),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class OnboardingSectionHeader extends StatelessWidget {
  const OnboardingSectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.trailing,
    this.onViewAll,
  });

  final String title;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          if (onViewAll != null)
            TextButton(
              onPressed: onViewAll,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'View all',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
            )
          else if (trailing != null) ...[
            const SizedBox(width: 8),
            Flexible(child: trailing!),
          ],
        ],
      ),
    );
  }
}

class OnboardingChipOption extends StatelessWidget {
  const OnboardingChipOption({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

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

class OnboardingSummaryRow extends StatelessWidget {
  const OnboardingSummaryRow(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class OnboardingErrorView extends StatelessWidget {
  const OnboardingErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

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
