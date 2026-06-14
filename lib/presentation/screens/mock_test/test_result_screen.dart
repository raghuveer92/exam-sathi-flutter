import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../../core/router/app_navigation.dart';
import '../../../data/models/mock_test_model.dart';
import '../../../data/repositories/mock_test_repository.dart';

class TestResultScreen extends StatefulWidget {
  final int topicId;
  final int attemptId;
  final MockTestAttemptModel? initialResult;

  const TestResultScreen({
    super.key,
    required this.topicId,
    required this.attemptId,
    this.initialResult,
  });

  @override
  State<TestResultScreen> createState() => _TestResultScreenState();
}

class _TestResultScreenState extends State<TestResultScreen> {
  static const _primary = Color(0xFF6C63FF);
  static const _primaryDark = Color(0xFF4F46E5);
  static const _success = Color(0xFF22A447);
  static const _danger = Color(0xFFFF4B3E);
  static const _warning = Color(0xFFFFB020);
  static const _screenBg = Color(0xFFFAFBFF);
  static const _border = Color(0xFFE7E8F3);
  static const _softPurple = Color(0xFFF1EFFF);
  static const _ink = Color(0xFF111827);
  static const _muted = Color(0xFF6B7280);

  MockTestAttemptModel? _result;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _result = widget.initialResult;
    if (_result == null || _result!.review.isEmpty) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _result = await GetIt.I<MockTestRepository>().getAttempt(
        widget.attemptId,
        review: true,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _result == null) {
      return const Scaffold(
        backgroundColor: _screenBg,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final result = _result!;
    return Scaffold(
      backgroundColor: _screenBg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                    child: _ResultHeader(
                      topicTitle: result.topicTitle,
                      onBack: () => AppNavigation.pop(context),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
                    child: _SummaryCard(result: result),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Detailed Review',
                            style: TextStyle(
                              color: _ink,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        _ReviewCountPill(count: result.review.length),
                      ],
                    ),
                  ),
                ),
                if (result.review.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: _EmptyReviewCard(),
                    ),
                  )
                else
                  SliverList.separated(
                    itemCount: result.review.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          index == 0 ? 0 : 0,
                          20,
                          index == result.review.length - 1 ? 20 : 0,
                        ),
                        child: _ReviewCard(
                          item: result.review[index],
                          questionNumber: index + 1,
                        ),
                      );
                    },
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 2, 20, 24),
                    child: _ActionBar(
                      onRetake: () => AppNavigation.goIfDifferent(
                        context,
                        '/mock-test/${widget.topicId}',
                      ),
                      onSubjects: () => AppNavigation.goIfDifferent(
                        context,
                        '/subjects',
                      ),
                    ),
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

class _ResultHeader extends StatelessWidget {
  final String topicTitle;
  final VoidCallback onBack;

  const _ResultHeader({
    required this.topicTitle,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _IconButtonShell(
          icon: Icons.arrow_back_ios_new_rounded,
          onPressed: onBack,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Test Result',
                style: TextStyle(
                  color: _TestResultScreenState._muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                topicTitle.isEmpty ? 'Mock Test' : topicTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _TestResultScreenState._ink,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final MockTestAttemptModel result;

  const _SummaryCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final percentage = (result.percentage ?? 0).clamp(0, 100).toDouble();
    final correct = result.correctCount ?? 0;
    final incorrect = result.incorrectCount ?? 0;
    final skipped = result.skippedCount ?? 0;
    final total = result.totalQuestions;
    final score = result.score ?? 0;
    final maxScore = result.maxScore ?? total.toDouble();
    final strength = _strengthLabel(percentage);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _TestResultScreenState._border),
        boxShadow: [
          BoxShadow(
            color: _TestResultScreenState._primary.withValues(alpha: 0.10),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 560;
              final ring = _ScoreRing(
                percentage: percentage,
                label: strength,
              );
              final body = _ScoreSummaryText(
                score: score,
                maxScore: maxScore,
                percentage: percentage,
                strength: strength,
              );
              if (compact) {
                return Column(
                  children: [
                    ring,
                    const SizedBox(height: 18),
                    body,
                  ],
                );
              }
              return Row(
                children: [
                  ring,
                  const SizedBox(width: 22),
                  Expanded(child: body),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: percentage / 100,
              backgroundColor: _TestResultScreenState._softPurple,
              valueColor: const AlwaysStoppedAnimation<Color>(
                _TestResultScreenState._primary,
              ),
            ),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 430 ? 2 : 4;
              final width =
                  (constraints.maxWidth - ((columns - 1) * 10)) / columns;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _MetricTile(
                    width: width,
                    icon: Icons.check_rounded,
                    iconColor: _TestResultScreenState._success,
                    label: 'Correct',
                    value: '$correct',
                  ),
                  _MetricTile(
                    width: width,
                    icon: Icons.close_rounded,
                    iconColor: _TestResultScreenState._danger,
                    label: 'Incorrect',
                    value: '$incorrect',
                  ),
                  _MetricTile(
                    width: width,
                    icon: Icons.remove_rounded,
                    iconColor: _TestResultScreenState._warning,
                    label: 'Skipped',
                    value: '$skipped',
                  ),
                  _MetricTile(
                    width: width,
                    icon: Icons.format_list_numbered_rounded,
                    iconColor: _TestResultScreenState._primary,
                    label: 'Total',
                    value: '$total',
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _strengthLabel(double percentage) {
    if (percentage >= 80) return 'Strong';
    if (percentage >= 60) return 'Good';
    if (percentage >= 40) return 'Keep going';
    return 'Needs practice';
  }
}

class _ScoreRing extends StatelessWidget {
  final double percentage;
  final String label;

  const _ScoreRing({
    required this.percentage,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      height: 150,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 136,
            height: 136,
            child: CircularProgressIndicator(
              strokeWidth: 13,
              value: percentage / 100,
              strokeCap: StrokeCap.round,
              backgroundColor: _TestResultScreenState._softPurple,
              valueColor: AlwaysStoppedAnimation<Color>(
                percentage >= 60
                    ? _TestResultScreenState._success
                    : _TestResultScreenState._primary,
              ),
            ),
          ),
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${percentage.toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: _TestResultScreenState._ink,
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: percentage >= 60
                        ? _TestResultScreenState._success
                        : _TestResultScreenState._primaryDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreSummaryText extends StatelessWidget {
  final double score;
  final double maxScore;
  final double percentage;
  final String strength;

  const _ScoreSummaryText({
    required this.score,
    required this.maxScore,
    required this.percentage,
    required this.strength,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _TestResultScreenState._softPurple,
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.workspace_premium_rounded,
                size: 18,
                color: _TestResultScreenState._primary,
              ),
              SizedBox(width: 7),
              Text(
                'Assessment complete',
                style: TextStyle(
                  color: _TestResultScreenState._primaryDark,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '${score.toStringAsFixed(1)} / ${maxScore.toStringAsFixed(1)}',
          style: const TextStyle(
            color: _TestResultScreenState._ink,
            fontSize: 32,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '$strength Understanding • ${percentage.toStringAsFixed(1)}% accuracy',
          style: const TextStyle(
            color: _TestResultScreenState._muted,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  final double width;
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _MetricTile({
    required this.width,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Container(
        constraints: const BoxConstraints(minHeight: 88),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFBFBFF),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _TestResultScreenState._border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: iconColor, size: 24),
            const SizedBox(height: 7),
            Text(
              value,
              style: const TextStyle(
                color: _TestResultScreenState._ink,
                fontSize: 21,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _TestResultScreenState._muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewCountPill extends StatelessWidget {
  final int count;

  const _ReviewCountPill({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _TestResultScreenState._border),
      ),
      child: Text(
        '$count Questions',
        style: const TextStyle(
          color: _TestResultScreenState._muted,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final MockTestReviewModel item;
  final int questionNumber;

  const _ReviewCard({
    required this.item,
    required this.questionNumber,
  });

  @override
  Widget build(BuildContext context) {
    final skipped = item.selectedOptionKeys.isEmpty;
    final statusColor = skipped
        ? _TestResultScreenState._warning
        : item.isCorrect
            ? _TestResultScreenState._success
            : _TestResultScreenState._danger;
    final statusLabel = skipped
        ? 'Skipped'
        : item.isCorrect
            ? 'Correct'
            : 'Incorrect';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$questionNumber',
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.questionText,
                  style: const TextStyle(
                    color: _TestResultScreenState._ink,
                    fontSize: 17,
                    height: 1.25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(
                color: statusColor,
                label: statusLabel,
                icon: skipped
                    ? Icons.remove_rounded
                    : item.isCorrect
                        ? Icons.check_rounded
                        : Icons.close_rounded,
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 460;
              final answerRows = [
                _AnswerChip(
                  label: 'Your answer',
                  value:
                      skipped ? 'Skipped' : item.selectedOptionKeys.join(', '),
                  color: skipped
                      ? _TestResultScreenState._warning
                      : _TestResultScreenState._primary,
                ),
                _AnswerChip(
                  label: 'Correct answer',
                  value: item.correctOptionKeys.isEmpty
                      ? '-'
                      : item.correctOptionKeys.join(', '),
                  color: _TestResultScreenState._success,
                ),
                _AnswerChip(
                  label: 'Marks',
                  value: _formatMarks(item.marksAwarded),
                  color: statusColor,
                ),
              ];

              if (compact) {
                return Column(
                  children: answerRows
                      .map(
                        (chip) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: chip,
                        ),
                      )
                      .toList(),
                );
              }

              return Row(
                children: [
                  for (final chip in answerRows) ...[
                    Expanded(child: chip),
                    if (chip != answerRows.last) const SizedBox(width: 8),
                  ],
                ],
              );
            },
          ),
          if (item.explanation != null && item.explanation!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _TestResultScreenState._border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.lightbulb_outline_rounded,
                      color: _TestResultScreenState._primary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item.explanation!.trim(),
                        style: const TextStyle(
                          color: _TestResultScreenState._muted,
                          fontSize: 14,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatMarks(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(1);
  }
}

class _StatusPill extends StatelessWidget {
  final Color color;
  final String label;
  final IconData icon;

  const _StatusPill({
    required this.color,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnswerChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _AnswerChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _TestResultScreenState._muted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyReviewCard extends StatelessWidget {
  const _EmptyReviewCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _TestResultScreenState._border),
      ),
      child: const Text(
        'Review details are not available for this attempt yet.',
        style: TextStyle(
          color: _TestResultScreenState._muted,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  final VoidCallback onRetake;
  final VoidCallback onSubjects;

  const _ActionBar({
    required this.onRetake,
    required this.onSubjects,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        final retake = OutlinedButton.icon(
          onPressed: onRetake,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retake Test'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _TestResultScreenState._primaryDark,
            side: const BorderSide(color: _TestResultScreenState._border),
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        );
        final subjects = ElevatedButton.icon(
          onPressed: onSubjects,
          icon: const Icon(Icons.grid_view_rounded),
          label: const Text('Back to Subjects'),
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: _TestResultScreenState._primary,
            minimumSize: const Size.fromHeight(56),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        );

        if (compact) {
          return Column(
            children: [
              retake,
              const SizedBox(height: 10),
              subjects,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: retake),
            const SizedBox(width: 12),
            Expanded(child: subjects),
          ],
        );
      },
    );
  }
}

class _IconButtonShell extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _IconButtonShell({
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _TestResultScreenState._border),
          ),
          child: Icon(
            icon,
            color: _TestResultScreenState._ink,
            size: 21,
          ),
        ),
      ),
    );
  }
}
