import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/dashboard_model.dart';

/// Weekly study hours bar chart for the Analytics screen.
class AnalyticsWeeklyChart extends StatelessWidget {
  final List<DailyLogModel> logs;

  const AnalyticsWeeklyChart({super.key, required this.logs});

  static const double _maxY = 12;

  List<({DateTime date, double hours})> _buildWeek() {
    final today = DateTime.now();
    final logMap = <String, double>{
      for (final l in logs) l.studyDate: l.hoursStudied,
    };
    return List.generate(7, (i) {
      final d = today.subtract(Duration(days: 6 - i));
      final key = DateFormat('yyyy-MM-dd').format(d);
      return (date: d, hours: logMap[key] ?? 0.0);
    });
  }

  String _formatHours(double hours) {
    if (hours == hours.roundToDouble()) {
      return '${hours.toInt()}h';
    }
    return '${hours.toStringAsFixed(1)}h';
  }

  @override
  Widget build(BuildContext context) {
    final week = _buildWeek();
    final totalHours = week.fold(0.0, (sum, e) => sum + e.hours);
    final hasData = totalHours > 0;
    final today = DateTime.now();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Weekly Study Hours',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
              ),
              Text(
                'Total: ${_formatHours(totalHours)}',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!hasData)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'No study hours recorded this week',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            )
          else
            SizedBox(
              height: 180,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 28,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(7, (i) {
                        final value = _maxY - (i * 2);
                        return Text(
                          '${value.toInt()}h',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: BarChart(
                      BarChartData(
                        maxY: _maxY,
                        minY: 0,
                        barTouchData: BarTouchData(
                          enabled: true,
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipColor: (_) =>
                                AppColors.primary.withValues(alpha: 0.92),
                            tooltipRoundedRadius: 8,
                            getTooltipItem: (group, _, rod, __) {
                              final entry = week[group.x];
                              final dateStr =
                                  DateFormat('d MMM').format(entry.date);
                              return BarTooltipItem(
                                _formatHours(entry.hours),
                                const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                                children: [
                                  TextSpan(
                                    text: '\n$dateStr',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                      fontWeight: FontWeight.normal,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        titlesData: FlTitlesData(
                          leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, _) {
                                final idx = value.toInt();
                                if (idx < 0 || idx >= 7) {
                                  return const SizedBox.shrink();
                                }
                                final d = week[idx].date;
                                final isToday = d.year == today.year &&
                                    d.month == today.month &&
                                    d.day == today.day;
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    DateFormat('E').format(d),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: isToday
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: isToday
                                          ? AppColors.primary
                                          : AppColors.textSecondary,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: 2,
                          getDrawingHorizontalLine: (_) => const FlLine(
                            color: AppColors.divider,
                            strokeWidth: 1,
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        barGroups: List.generate(7, (i) {
                          final entry = week[i];
                          final isToday = entry.date.year == today.year &&
                              entry.date.month == today.month &&
                              entry.date.day == today.day;
                          final barHeight =
                              entry.hours.clamp(0.0, _maxY).toDouble();
                          return BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: barHeight,
                                width: 22,
                                borderRadius: BorderRadius.circular(6),
                                gradient: LinearGradient(
                                  colors: isToday
                                      ? [
                                          AppColors.primary,
                                          AppColors.secondary,
                                        ]
                                      : [
                                          AppColors.primary
                                              .withValues(alpha: 0.75),
                                          AppColors.secondary
                                              .withValues(alpha: 0.75),
                                        ],
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                ),
                                backDrawRodData: BackgroundBarChartRodData(
                                  show: true,
                                  toY: _maxY,
                                  color: isToday
                                      ? AppColors.primary.withValues(alpha: 0.1)
                                      : AppColors.primary
                                          .withValues(alpha: 0.05),
                                ),
                              ),
                            ],
                          );
                        }),
                      ),
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
