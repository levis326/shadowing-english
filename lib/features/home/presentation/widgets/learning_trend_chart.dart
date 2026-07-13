import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../learning_dashboard_provider.dart';

class LearningTrendChart extends StatelessWidget {
  const LearningTrendChart({required this.trend, super.key});

  final List<LearningTrendPoint> trend;

  @override
  Widget build(BuildContext context) {
    final int maxMinutes = trend.fold<int>(
      1,
      (int maxValue, LearningTrendPoint item) =>
          item.studyMinutes > maxValue ? item.studyMinutes : maxValue,
    );
    final int labelStep = trend.length <= 7 ? 1 : (trend.length / 5).ceil();

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (trend.length - 1).toDouble(),
        minY: 0,
        maxY: (maxMinutes * 1.25).ceilToDouble(),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: maxMinutes <= 5
              ? 1
              : (maxMinutes / 3).ceilToDouble(),
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppDesignTokens.softGray, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: labelStep.toDouble(),
              getTitlesWidget: (double value, TitleMeta meta) {
                final int index = value.round();
                if (index < 0 ||
                    index >= trend.length ||
                    index % labelStep != 0) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    trend[index].label,
                    style: const TextStyle(
                      color: AppDesignTokens.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (List<LineBarSpot> touchedSpots) => touchedSpots
                .map(
                  (LineBarSpot spot) => LineTooltipItem(
                    '${trend[spot.x.round()].studyMinutes} 分钟',
                    const TextStyle(
                      color: AppDesignTokens.appWhite,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ),
        lineBarsData: <LineChartBarData>[
          LineChartBarData(
            isCurved: true,
            curveSmoothness: 0.28,
            color: AppDesignTokens.brandGreen,
            barWidth: 5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: trend.length <= 7,
              getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                radius: 4,
                color: AppDesignTokens.appWhite,
                strokeWidth: 3,
                strokeColor: AppDesignTokens.brandGreen,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Color(0x6658CC02), Color(0x0058CC02)],
              ),
            ),
            spots: <FlSpot>[
              for (int index = 0; index < trend.length; index++)
                FlSpot(index.toDouble(), trend[index].studyMinutes.toDouble()),
            ],
          ),
        ],
      ),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }
}
