import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mac_fan_tool/src/dashboard/dashboard_colors.dart';
import 'package:mac_fan_tool/src/dashboard/dashboard_state.dart';
import 'package:mac_fan_tool/src/dashboard/dashboard_support.dart';
import 'package:mac_fan_tool/src/dashboard/thermal_trend.dart';
import 'package:mac_fan_tool/src/dashboard/widgets/dashboard_common.dart';

class OverviewView extends ConsumerWidget {
  const OverviewView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(summaryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          spacing: 16,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: MetricCard(
                label: 'CPU',
                value: formatTemperature(summary.cpuAverage),
                caption: compactSensorCountLabel(summary.cpuSensorCount),
                accentColor: DashboardColors.cpu,
              ),
            ),
            Expanded(
              child: MetricCard(
                label: 'GPU',
                value: formatTemperature(summary.gpuAverage),
                caption: compactSensorCountLabel(summary.gpuSensorCount),
                accentColor: DashboardColors.gpu,
              ),
            ),
            Expanded(
              child: MetricCard(
                label: 'Power',
                value: formatTemperature(summary.powerAverage),
                caption: compactSensorCountLabel(summary.powerSensorCount),
                accentColor: DashboardColors.power,
              ),
            ),
            Expanded(
              child: MetricCard(
                label: 'Disk',
                value: formatTemperature(summary.diskAverage),
                caption: compactSensorCountLabel(summary.diskSensorCount),
                accentColor: DashboardColors.disk,
              ),
            ),
            Expanded(
              child: MetricCard(
                label: 'Memory',
                value: formatTemperature(summary.memoryAverage),
                caption: compactSensorCountLabel(summary.memorySensorCount),
                accentColor: DashboardColors.memory,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const _ThermalTrendPanel(),
      ],
    );
  }
}

class _ThermalTrendPanel extends ConsumerWidget {
  const _ThermalTrendPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trend = ref.watch(thermalTrendProvider);

    return SectionPanel(
      title: 'Thermal Trend',
      subtitle:
          'Composite, CPU average, and GPU average over the recent polling window.',
      child: trend.isEmpty
          ? const EmptyPanel(
              icon: Icons.show_chart,
              message:
                  'The chart appears once at least two aggregated samples are available.',
            )
          : Column(
              children: [
                _ThermalTrendChart(trend: trend),
                const SizedBox(height: 18),
                _ThermalTrendLegend(series: trend.visibleSeries),
              ],
            ),
    );
  }
}

class _ThermalTrendChart extends StatelessWidget {
  const _ThermalTrendChart({required this.trend});

  final ThermalTrendModel trend;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 240,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: trend.maxX,
          minY: trend.minY,
          maxY: trend.maxY,
          lineTouchData: const LineTouchData(enabled: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: trend.interval,
            getDrawingHorizontalLine: (_) => const FlLine(
              color: DashboardColors.chartGrid,
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 48,
                interval: trend.interval,
                getTitlesWidget: (value, meta) {
                  return Text(
                    '${value.toStringAsFixed(0)}°',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: DashboardColors.textChart,
                    ),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            for (final item in trend.series)
              LineChartBarData(
                isCurved: true,
                barWidth: 3,
                color: item.color,
                dotData: const FlDotData(show: false),
                belowBarData: item.fillColor == null
                    ? BarAreaData(show: false)
                    : BarAreaData(show: true, color: item.fillColor),
                spots: [
                  for (final point in item.points) FlSpot(point.x, point.y),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ThermalTrendLegend extends StatelessWidget {
  const _ThermalTrendLegend({required this.series});

  final List<ThermalTrendSeries> series;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 10,
      children: [
        for (final item in series)
          LegendChip(color: item.color, label: item.label),
      ],
    );
  }
}
