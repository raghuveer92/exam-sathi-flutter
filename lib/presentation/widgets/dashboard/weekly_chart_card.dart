import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/dashboard_model.dart';

/// Bar chart always showing the last 7 days (including days with 0 hours).
class WeeklyChartCard extends StatelessWidget {
  final List<DailyLogModel> logs;

  const WeeklyChartCard({super.key, required this.logs});

  /// Build a 7-entry list anchored to today, filling missing days with 0h.
  List<({DateTime date, double hours})> _buildWeek() {
    final today = DateTime.now();
    // Map studyDate (YYYY-MM-DD) → hours
    final logMap = <String, double>{
      for (final l in logs) l.studyDate: l.hoursStudied,
    };
    return List.generate(7, (i) {
      final d = today.subtract(Duration(days: 6 - i));
      final key =
          '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      return (date: d, hours: logMap[key] ?? 0.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final week = _buildWeek();
    final maxHours =
        week.fold<double>(0.0, (p, e) => e.hours > p ? e.hours : p) + 1;
    final totalHours = week.fold(0.0, (s, e) => s + e.hours);
    final today = DateTime.now();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: AppColors.shadow,
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('This Week',
                  style: Theme.of(context).textTheme.titleLarge),
              Text(
                'Total: ${totalHours.toStringAsFixed(1)}h',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final chartHeight =
                  constraints.maxWidth > 700 ? 200.0 : 130.0;
              final barWidth =
                  constraints.maxWidth > 700 ? 26.0 : 20.0;
              return SizedBox(
                height: chartHeight,
                child: BarChart(
                  BarChartData(
                    maxY: maxHours,
                    barTouchData: BarTouchData(
                      enabled: true,
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipColor: (_) =>
                            AppColors.primary.withOpacity(0.92),
                        tooltipRoundedRadius: 8,
                        getTooltipItem: (group, _, rod, __) {
                          final entry = week[group.x];
                          final dateStr =
                              DateFormat('d MMM').format(entry.date);
                          return BarTooltipItem(
                            '${entry.hours.toStringAsFixed(1)}h',
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
                          sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
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
                                DateFormat('E').format(d), // Mon, Tue…
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: isToday
                                      ? FontWeight.w700
                                      : FontWeight.normal,
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
                      horizontalInterval: maxHours / 4,
                      getDrawingHorizontalLine: (_) => const FlLine(
                        color: AppColors.divider,
                        strokeWidth: 1,
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    barGroups: List.generate(7, (i) {
                      final entry = week[i];
                      final isEmpty = entry.hours == 0;
                      return BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: isEmpty ? 0.0 : entry.hours,
                            gradient: isEmpty
                                ? null
                                : const LinearGradient(
                                    colors: [
                                      AppColors.primary,
                                      AppColors.secondary
                                    ],
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                  ),
                            color: isEmpty
                                ? AppColors.primary.withOpacity(0.0)
                                : null,
                            width: barWidth,
                            borderRadius: BorderRadius.circular(6),
                            backDrawRodData: BackgroundBarChartRodData(
                              show: true,
                              toY: maxHours,
                              color: isEmpty
                                  ? AppColors.primary.withOpacity(0.06)
                                  : AppColors.primary.withOpacity(0.05),
                            ),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
