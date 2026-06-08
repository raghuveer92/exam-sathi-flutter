import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/models/dashboard_model.dart';

/// Dashboard hero card — matches reference layout (Overall Progress + Daily Target).
class OverallProgressCard extends StatelessWidget {
  final DashboardModel dashboard;

  const OverallProgressCard({super.key, required this.dashboard});

  static const Color _purple = Color(0xFF6366F1);
  static const Color _purpleLight = Color(0xFFEEF2FF);
  static const Color _green = Color(0xFF34D399);
  static const Color _greenDark = Color(0xFF10B981);
  static const Color _greenLight = Color(0xFFECFDF5);
  static const Color _greenIconBg = Color(0xFFD1FAE5);
  static const Color _textDark = Color(0xFF111827);
  static const Color _textGray = Color(0xFF6B7280);
  static const Color _trackGray = Color(0xFFE5E7EB);

  @override
  Widget build(BuildContext context) {
    final completed = dashboard.completedTopics;
    final total = dashboard.totalTopics;
    final overallPercent =
        total == 0 ? 0.0 : (completed * 100.0 / total).clamp(0.0, 100.0);
    final overallRatio = overallPercent / 100;

    final dailyTarget = dashboard.effectiveDailyTargetHours;
    final todayStudied = dashboard.todayHours;
    final hasDailyTarget = dailyTarget > 0;
    final goalAchieved = hasDailyTarget && todayStudied >= dailyTarget;
    final dailyPercent = !hasDailyTarget
        ? 0
        : (todayStudied / dailyTarget * 100).round();
    final dailyRingValue = !hasDailyTarget
        ? 0.0
        : (todayStudied / dailyTarget).clamp(0.0, 1.0);
    final remaining =
        hasDailyTarget ? math.max(0.0, dailyTarget - todayStudied) : 0.0;

    final isEmptyUser = completed == 0 && todayStudied <= 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildOverallSection(
            percent: overallPercent,
            completed: completed,
            total: total,
            ratio: overallRatio,
            isEmptyUser: isEmptyUser,
          ),
          const SizedBox(height: 18),
          const Divider(height: 1, thickness: 1, color: Color(0xFFF3F4F6)),
          const SizedBox(height: 18),
          _buildDailySection(
            dailyPercent: dailyPercent,
            dailyRingValue: dailyRingValue,
            todayStudied: todayStudied,
            dailyTarget: dailyTarget,
            hasDailyTarget: hasDailyTarget,
            goalAchieved: goalAchieved,
            remaining: remaining,
            isEmptyUser: isEmptyUser,
          ),
          const SizedBox(height: 14),
          _buildBottomPanel(
            isEmptyUser: isEmptyUser,
            goalAchieved: goalAchieved,
          ),
        ],
      ),
    );
  }

  Widget _buildOverallSection({
    required double percent,
    required int completed,
    required int total,
    required double ratio,
    required bool isEmptyUser,
  }) {
    final topicsLabel = isEmptyUser || (completed == 0 && total == 0)
        ? 'No topics completed yet'
        : '$completed / $total Topics Completed';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _sectionIcon(
              icon: Icons.show_chart_rounded,
              iconColor: _purple,
              background: _purpleLight,
            ),
            const SizedBox(width: 11),
            const Text(
              'Overall Progress',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _textDark,
                height: 1.1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        Text(
          '${percent.round()}%',
          style: const TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w800,
            color: _purple,
            height: 1,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          topicsLabel,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: _textGray,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 11),
        _GradientLinearProgress(value: ratio),
        const SizedBox(height: 6),
        const Row(
          children: [
            Text(
              '0%',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: _textGray,
              ),
            ),
            Spacer(),
            Text(
              '50%',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: _textGray,
              ),
            ),
            Spacer(),
            Text(
              '100%',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: _textGray,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDailySection({
    required int dailyPercent,
    required double dailyRingValue,
    required double todayStudied,
    required double dailyTarget,
    required bool hasDailyTarget,
    required bool goalAchieved,
    required double remaining,
    required bool isEmptyUser,
  }) {
    final studiedText = _fmtHours(todayStudied);
    final targetText =
        hasDailyTarget ? _fmtHours(dailyTarget) : 'Target';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _sectionIcon(
              icon: Icons.track_changes_rounded,
              iconColor: _greenDark,
              background: _greenIconBg,
            ),
            const SizedBox(width: 11),
            const Text(
              'Daily Target',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _textDark,
                height: 1.1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 13),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _GradientCircularProgress(
              percent: dailyPercent,
              progress: dailyRingValue,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(height: 1.15),
                      children: [
                        TextSpan(
                          text: studiedText,
                          style: const TextStyle(
                            fontSize: 27,
                            fontWeight: FontWeight.w800,
                            color: _textDark,
                          ),
                        ),
                        TextSpan(
                          text: ' / $targetText',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: _textGray,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Today',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _purple,
                    ),
                  ),
                  if (goalAchieved) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Daily Goal Achieved 🎉',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _greenDark,
                        height: 1.3,
                      ),
                    ),
                  ] else if (!isEmptyUser && hasDailyTarget && remaining > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(
                            Icons.schedule_rounded,
                            size: 14,
                            color: _textGray.withValues(alpha: 0.85),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_fmtHours(remaining)} remaining',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: _textGray,
                                  height: 1.3,
                                ),
                              ),
                              const Text(
                                'to reach today\'s goal',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: _textGray,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBottomPanel({
    required bool isEmptyUser,
    required bool goalAchieved,
  }) {
    final String title;
    final String subtitle;
    final Color titleColor;

    if (isEmptyUser) {
      title = 'Ready to begin?';
      subtitle = 'Start your first topic to begin tracking progress.';
      titleColor = _purple;
    } else if (goalAchieved) {
      title = 'Daily Goal Achieved!';
      subtitle = 'Great work today. Keep the momentum going!';
      titleColor = _greenDark;
    } else {
      title = 'Keep going!';
      subtitle = 'You\'re doing great. Stay consistent!';
      titleColor = _greenDark;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: _greenLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                goalAchieved || !isEmptyUser
                    ? Icons.emoji_events_rounded
                    : Icons.auto_awesome_rounded,
                size: 16,
                color: goalAchieved || !isEmptyUser
                    ? const Color(0xFFF59E0B)
                    : _purple,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: titleColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _textGray,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionIcon({
    required IconData icon,
    required Color iconColor,
    required Color background,
  }) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 18, color: iconColor),
    );
  }

  String _fmtHours(double hours) {
    if (hours <= 0) return '0h';
    final totalMinutes = (hours * 60).round();
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }
}

class _GradientLinearProgress extends StatelessWidget {
  const _GradientLinearProgress({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: OverallProgressCard._trackGray),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0.0, 1.0),
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF818CF8),
                      OverallProgressCard._purple,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradientCircularProgress extends StatelessWidget {
  const _GradientCircularProgress({
    required this.percent,
    required this.progress,
  });

  final int percent;
  final double progress;

  static const double _size = 93;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(_size, _size),
            painter: _GradientRingPainter(
              progress: progress,
              strokeWidth: 7,
              trackColor: OverallProgressCard._trackGray,
              gradientColors: const [
                Color(0xFF6EE7B7),
                OverallProgressCard._green,
                OverallProgressCard._greenDark,
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '$percent%',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: OverallProgressCard._greenDark,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Completed',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: OverallProgressCard._textGray,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GradientRingPainter extends CustomPainter {
  _GradientRingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.trackColor,
    required this.gradientColors,
  });

  final double progress;
  final double strokeWidth;
  final Color trackColor;
  final List<Color> gradientColors;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    if (progress <= 0) return;

    final sweep = 2 * math.pi * progress.clamp(0.0, 1.0);
    final progressPaint = Paint()
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: 3 * math.pi / 2,
        colors: gradientColors,
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GradientRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
