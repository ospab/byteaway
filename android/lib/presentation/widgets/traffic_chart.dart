import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../domain/entities/traffic_record.dart';
import '../theme/app_theme.dart';

/// Bar chart showing daily traffic (shared and consumed) for the last N days.
class TrafficChart extends StatelessWidget {
  final List<TrafficRecord> records;
  final bool showConsumed;

  const TrafficChart({
    super.key,
    required this.records,
    this.showConsumed = true,
  });

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(
          child: Text(
            'Нет данных о трафике',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
      );
    }

    final maxY = records.fold<double>(0, (max, r) {
      final shared = r.sharedGb;
      final consumed = r.consumedGb;
      final localMax = shared > consumed ? shared : consumed;
      return localMax > max ? localMax : max;
    });

    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: (maxY * 1.3).clamp(0.1, double.infinity),
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              tooltipRoundedRadius: 8,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final record = records[group.x.toInt()];
                final label = rodIndex == 0 ? 'Отдано' : 'Потреблено';
                final value = rodIndex == 0 ? record.sharedGb : record.consumedGb;
                return BarTooltipItem(
                  '$label: ${value.toStringAsFixed(2)} GB',
                  const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= records.length) {
                    return const SizedBox.shrink();
                  }
                  // Show every other label to avoid overlap
                  if (records.length > 7 && idx % 2 != 0) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      DateFormat('dd.MM').format(records[idx].date),
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  return Text(
                    '${value.toStringAsFixed(1)}G',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 10,
                    ),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY > 0 ? maxY / 4 : 0.25,
            getDrawingHorizontalLine: (value) => FlLine(
              color: AppTheme.textSecondary.withOpacity(0.1),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: _buildBarGroups(),
        ),
        swapAnimationDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  List<BarChartGroupData> _buildBarGroups() {
    return List.generate(records.length, (i) {
      final record = records[i];
      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: record.sharedGb,
            color: AppTheme.primary,
            width: showConsumed ? 8 : 14,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
          if (showConsumed)
            BarChartRodData(
              toY: record.consumedGb,
              color: AppTheme.accent,
              width: 8,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(4)),
            ),
        ],
      );
    });
  }
}
