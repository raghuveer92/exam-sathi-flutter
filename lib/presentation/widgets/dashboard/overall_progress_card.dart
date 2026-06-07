import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/models/dashboard_model.dart';

/// Compact dashboard hero — overall syllabus progress + today's study target.
class OverallProgressCard extends StatelessWidget {
  final DashboardModel dashboard;

  const OverallProgressCard({super.key, required this.dashboard});

  static const Color _overallBlue = Color(0xFF3B82F6);
  static const Color _dailyGreen = Color(0xFF22A96B);

  @override
  Widget build(BuildContext context) {
    final completed = dashboard.completedTopics;
    final total = dashboard.totalTopics;
    final overallPercent =
        total == 0 ? 0.0 : (completed * 100.0 / total).clamp(0.0, 100.0);
    final overallRatio = overallPercent / 100;

    final dailyTarget = dashboard.user.dailyTargetHours ?? 0.0;
    final todayStudied = dashboard.todayHours;
    final dailyRatio = dailyTarget <= 0
        ? 0.0
        : (todayStudied / dailyTarget).clamp(0.0, 1.0);
    final dailyPercent = (dailyRatio * 100).round();
    final remaining =
        dailyTarget <= 0 ? 0.0 : math.max(0.0, dailyTarget - todayStudied);

    final isFirstTime = completed == 0 && todayStudied <= 0;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFDFDFF),
            Color(0xFFF3F5FF),
            Color(0xFFF8FAFF),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE6E9F4)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6C63FF).withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
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
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFEDEEF6)),
          _buildDailySection(
            dailyPercent: dailyPercent,
            dailyRatio: dailyRatio,
            todayStudied: todayStudied,
            dailyTarget: dailyTarget,
            remaining: remaining,
            isFirstTime: isFirstTime,
          ),
          if (isFirstTime) ...[
            const Divider(height: 1, thickness: 1, color: Color(0xFFEDEEF6)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Text(
                'Start your first topic to begin tracking progress.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: const Color(0xFF6C63FF).withValues(alpha: 0.9),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOverallSection({
    required double percent,
    required int completed,
    required int total,
    required double ratio,
  }) {
    final topicsLabel = total == 0
        ? '$completed Topics Completed'
        : '$completed / $total Topics Completed';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _sectionIcon(
                icon: Icons.show_chart_rounded,
                color: _overallBlue,
                background: const Color(0xFFEAF2FF),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Overall Progress',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1D26),
                  ),
                ),
              ),
              Text(
                '${percent.round()}%',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: _overallBlue,
                  height: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            topicsLabel,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF7A7F8F),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: const Color(0xFFE8ECF8),
              valueColor: const AlwaysStoppedAnimation<Color>(_overallBlue),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailySection({
    required int dailyPercent,
    required double dailyRatio,
    required double todayStudied,
    required double dailyTarget,
    required double remaining,
    required bool isFirstTime,
  }) {
    final hoursLine = dailyTarget <= 0
        ? '${_fmtHours(todayStudied)} / Daily Target'
        : '${_fmtHours(todayStudied)} / ${_fmtHours(dailyTarget)} Today';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _sectionIcon(
                icon: Icons.track_changes_rounded,
                color: _dailyGreen,
                background: const Color(0xFFE8F8EF),
              ),
              const SizedBox(width: 10),
              const Text(
                'Daily Target',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1D26),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: dailyRatio,
                      strokeWidth: 7,
                      backgroundColor: const Color(0xFFE8F8EF),
                      valueColor: const AlwaysStoppedAnimation<Color>(_dailyGreen),
                    ),
                    Text(
                      '$dailyPercent%',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _dailyGreen,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hoursLine,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1D26),
                        height: 1.2,
                      ),
                    ),
                    if (!isFirstTime && dailyTarget > 0) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 15,
                            color: _dailyGreen.withValues(alpha: 0.85),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${_fmtHours(remaining)} Remaining',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF7A7F8F),
                              fontWeight: FontWeight.w600,
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
      ),
    );
  }

  Widget _sectionIcon({
    required IconData icon,
    required Color color,
    required Color background,
  }) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }

  String _fmtHours(double hours) {
    if (hours == hours.roundToDouble()) {
      return '${hours.toInt()}h';
    }
    return '${hours.toStringAsFixed(1)}h';
  }
}
