import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/mock_test_model.dart';
import '../../../data/models/topic_model.dart';

/// Compact topic card palette — list-friendly, ~76–110px height.
class TopicAssessmentPalette {
  TopicAssessmentPalette._();

  static const borderColor = Color(0xFFE5E7EB);
  static const cardRadius = 16.0;
  static const cardShadow = BoxShadow(
    color: Color(0x08000000),
    blurRadius: 8,
    offset: Offset(0, 1),
  );

  static const primaryBlue = Color(0xFF2563EB);
  static const primaryBlueBg = Color(0xFFEFF6FF);

  static const notTested = Color(0xFF9CA3AF);
  static const notTestedBg = Color(0xFFF3F4F6);
  static const weak = Color(0xFFEF4444);
  static const weakBg = Color(0xFFFEF2F2);
  static const average = Color(0xFFF97316);
  static const averageBg = Color(0xFFFFF7ED);
  static const strong = Color(0xFF22C55E);
  static const strongBg = Color(0xFFF0FDF4);
  static const mastered = Color(0xFF9333EA);
  static const masteredBg = Color(0xFFF3E8FF);
  static const primaryGreen = Color(0xFF22C55E);
  static const textPrimary = Color(0xFF111827);
  static const textSecondary = Color(0xFF6B7280);

  static const titleStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.1,
  );
  static const metaStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.2,
  );
  static const chipStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.1,
  );
  static const percentStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.1,
  );
}

class TopicUnderstandingStyle {
  final String label;
  final Color accent;
  final Color background;

  const TopicUnderstandingStyle({
    required this.label,
    required this.accent,
    required this.background,
  });

  static TopicUnderstandingStyle forTopic(TopicModel topic) {
    if (!topic.hasAssessment) {
      return const TopicUnderstandingStyle(
        label: 'Test your understanding',
        accent: TopicAssessmentPalette.notTested,
        background: TopicAssessmentPalette.notTestedBg,
      );
    }
    return fromScore(topic.masteryScore ?? 0);
  }

  static TopicUnderstandingStyle fromScore(double score) {
    if (score >= 90) {
      return const TopicUnderstandingStyle(
        label: 'Mastered',
        accent: TopicAssessmentPalette.mastered,
        background: TopicAssessmentPalette.masteredBg,
      );
    }
    if (score >= 70) {
      return const TopicUnderstandingStyle(
        label: 'Strong',
        accent: TopicAssessmentPalette.strong,
        background: TopicAssessmentPalette.strongBg,
      );
    }
    if (score >= 40) {
      return const TopicUnderstandingStyle(
        label: 'Average',
        accent: TopicAssessmentPalette.average,
        background: TopicAssessmentPalette.averageBg,
      );
    }
    return const TopicUnderstandingStyle(
      label: 'Weak',
      accent: TopicAssessmentPalette.weak,
      background: TopicAssessmentPalette.weakBg,
    );
  }
}

/// Compact completed-topic card with inline test status (~76–110px).
class CompletedTopicAssessmentCard extends StatelessWidget {
  final TopicModel topic;
  final MockTestAttemptModel? latestResult;
  final String studyMetaLine;
  final VoidCallback onStartTest;
  final VoidCallback? onViewPerformance;
  final VoidCallback onRetake;

  const CompletedTopicAssessmentCard({
    super.key,
    required this.topic,
    this.latestResult,
    required this.studyMetaLine,
    required this.onStartTest,
    this.onViewPerformance,
    required this.onRetake,
  });

  @override
  Widget build(BuildContext context) {
    final hasAssessment = topic.hasAssessment;
    final score = topic.masteryScore ?? 0;
    final resultScore = latestResult?.percentage ?? score;

    return Material(
      color: Colors.white,
      elevation: 0,
      shadowColor: Colors.transparent,
      borderRadius: BorderRadius.circular(TopicAssessmentPalette.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: hasAssessment ? onViewPerformance : onStartTest,
        borderRadius: BorderRadius.circular(TopicAssessmentPalette.cardRadius),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius:
                BorderRadius.circular(TopicAssessmentPalette.cardRadius),
            border: Border.all(color: TopicAssessmentPalette.borderColor),
            boxShadow: const [TopicAssessmentPalette.cardShadow],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF43A047),
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          topic.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TopicAssessmentPalette.titleStyle,
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(
                              Icons.schedule_rounded,
                              size: 14,
                              color: TopicAssessmentPalette.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                hasAssessment
                                    ? '$studyMetaLine • ${resultScore.round()}%'
                                    : '$studyMetaLine • 100%',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TopicAssessmentPalette.metaStyle,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  hasAssessment
                      ? _RetakePill(onPressed: onRetake)
                      : _TestPill(onPressed: onStartTest),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(
                  height: 1, color: TopicAssessmentPalette.borderColor),
              const SizedBox(height: 12),
              if (!hasAssessment)
                _BeforeTestContent(onPressed: onStartTest)
              else
                _AfterTestContent(
                  result: latestResult,
                  score: resultScore,
                  style: TopicUnderstandingStyle.fromScore(resultScore),
                  onViewPerformance: onViewPerformance,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TestPill extends StatelessWidget {
  final VoidCallback onPressed;

  const _TestPill({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TopicAssessmentPalette.primaryBlueBg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Test',
            style: TextStyle(
              color: TopicAssessmentPalette.primaryBlue,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _RetakePill extends StatelessWidget {
  final VoidCallback onPressed;

  const _RetakePill({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TopicAssessmentPalette.strongBg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.refresh_rounded,
                size: 16,
                color: TopicAssessmentPalette.primaryGreen,
              ),
              SizedBox(width: 5),
              Text(
                'Retake',
                style: TextStyle(
                  color: TopicAssessmentPalette.primaryGreen,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BeforeTestContent extends StatelessWidget {
  final VoidCallback onPressed;

  const _BeforeTestContent({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: TopicAssessmentPalette.primaryBlueBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFDBEAFE)),
            ),
            child: const Icon(
              Icons.assignment_outlined,
              color: TopicAssessmentPalette.primaryBlue,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Test Your Understanding',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: TopicAssessmentPalette.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Take a quick test to know your strength in this topic.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: TopicAssessmentPalette.textSecondary,
                    fontSize: 13,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.chevron_right_rounded,
            color: TopicAssessmentPalette.primaryBlue,
            size: 28,
          ),
        ],
      ),
    );
  }
}

class _AfterTestContent extends StatelessWidget {
  final MockTestAttemptModel? result;
  final double score;
  final TopicUnderstandingStyle style;
  final VoidCallback? onViewPerformance;

  const _AfterTestContent({
    required this.result,
    required this.score,
    required this.style,
    this.onViewPerformance,
  });

  @override
  Widget build(BuildContext context) {
    final correct = result?.correctCount;
    final incorrect = result?.incorrectCount;
    final total = result?.totalQuestions;
    final maxScore = result?.maxScore;
    final scoreValue = result?.score;
    final scoreText = scoreValue != null && maxScore != null
        ? '${_fmtNumber(scoreValue)} / ${_fmtNumber(maxScore)}'
        : '${score.round()}%';

    return Column(
      children: [
        InkWell(
          onTap: onViewPerformance,
          borderRadius: BorderRadius.circular(12),
          child: Row(
            children: [
              _ScoreRing(score: score, style: style),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Score: $scoreText',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: TopicAssessmentPalette.primaryGreen,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${style.label} Understanding',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TopicAssessmentPalette.metaStyle,
                    ),
                    const SizedBox(height: 10),
                    _MasteryProgressBar(
                        value: score / 100, accent: style.accent),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: TopicAssessmentPalette.primaryGreen,
                size: 28,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Divider(height: 1, color: TopicAssessmentPalette.borderColor),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _ResultStat(
                icon: Icons.check_rounded,
                iconColor: TopicAssessmentPalette.primaryGreen,
                value: correct?.toString() ?? '-',
                label: 'Correct',
              ),
            ),
            const _StatDivider(),
            Expanded(
              child: _ResultStat(
                icon: Icons.close_rounded,
                iconColor: TopicAssessmentPalette.weak,
                value: incorrect?.toString() ??
                    (total != null && correct != null
                        ? (total - correct).toString()
                        : '-'),
                label: 'Incorrect',
              ),
            ),
            const _StatDivider(),
            Expanded(
              child: _ResultStat(
                icon: Icons.schedule_rounded,
                iconColor: TopicAssessmentPalette.primaryBlue,
                value: '${score.round()}%',
                label: 'Accuracy',
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _fmtNumber(double value) {
    final fixed = value.toStringAsFixed(1);
    return fixed.endsWith('.0') ? value.toInt().toString() : fixed;
  }
}

class _ScoreRing extends StatelessWidget {
  final double score;
  final TopicUnderstandingStyle style;

  const _ScoreRing({required this.score, required this.style});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: CircularProgressIndicator(
              value: (score / 100).clamp(0.0, 1.0),
              strokeWidth: 8,
              backgroundColor: TopicAssessmentPalette.borderColor,
              valueColor: AlwaysStoppedAnimation<Color>(style.accent),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${score.round()}%',
                style: TextStyle(
                  color: style.accent,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                style.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: style.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResultStat extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _ResultStat({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: iconColor.withValues(alpha: 0.12),
          ),
          child: Icon(icon, color: iconColor, size: 16),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: TopicAssessmentPalette.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: TopicAssessmentPalette.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 34,
      color: TopicAssessmentPalette.borderColor,
    );
  }
}

class _MasteryProgressBar extends StatelessWidget {
  final double value;
  final Color accent;

  const _MasteryProgressBar({required this.value, required this.accent});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 4,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFFE5E7EB)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0.0, 1.0),
              child: ColoredBox(color: accent),
            ),
          ],
        ),
      ),
    );
  }
}
