import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mac_fan_tool/src/dashboard/dashboard_colors.dart';
import 'package:mac_fan_tool/src/dashboard/dashboard_state.dart';
import 'package:mac_fan_tool/src/dashboard/dashboard_summary.dart';
import 'package:mac_fan_tool/src/dashboard/dashboard_support.dart';
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
  const _ThermalTrendPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(monitorHistoryProvider);

    final summaries = history
        .map((snapshot) => DashboardSummary.fromSnapshot(snapshot))
        .toList();
    final series = _buildTrendSeries(summaries);

    return SectionPanel(
      title: 'Thermal Trend',
      subtitle:
          'Composite, CPU average, and GPU average over the recent polling window.',
      child: series.every((item) => item.spots.length < 2)
          ? const EmptyPanel(
              icon: Icons.show_chart,
              message:
                  'The chart appears once at least two aggregated samples are available.',
            )
          : Column(
              children: [
                SizedBox(
                  height: 240,
                  child: LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: _trendMaxX(series),
                      minY: _trendMinY(series),
                      maxY: _trendMaxY(series),
                      lineTouchData: const LineTouchData(enabled: false),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: _trendInterval(series),
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
                            interval: _trendInterval(series),
                            getTitlesWidget: (value, meta) {
                              return Text(
                                '${value.toStringAsFixed(0)}°',
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: DashboardColors.textChart,
                                    ),
                              );
                            },
                          ),
                        ),
                      ),
                      lineBarsData: [
                        for (final item in series)
                          LineChartBarData(
                            isCurved: true,
                            barWidth: 3,
                            color: item.color,
                            dotData: const FlDotData(show: false),
                            belowBarData: item.fillColor == null
                                ? BarAreaData(show: false)
                                : BarAreaData(
                                    show: true,
                                    color: item.fillColor,
                                  ),
                            spots: item.spots,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 14,
                  runSpacing: 10,
                  children: [
                    for (final item in series.where(
                      (series) => series.spots.isNotEmpty,
                    ))
                      LegendChip(color: item.color, label: item.label),
                  ],
                ),
              ],
            ),
    );
  }
}

class _TrendSeries {
  const _TrendSeries({
    required this.label,
    required this.color,
    required this.spots,
    this.fillColor,
  });

  final String label;
  final Color color;
  final List<FlSpot> spots;
  final Color? fillColor;
}

List<_TrendSeries> _buildTrendSeries(List<DashboardSummary> summaries) {
  List<FlSpot> buildSpots(double? Function(DashboardSummary) selector) {
    final spots = <FlSpot>[];
    for (final entry in summaries.asMap().entries) {
      final value = selector(entry.value);
      if (value != null) {
        spots.add(FlSpot(entry.key.toDouble(), value));
      }
    }
    return spots;
  }

  return [
    _TrendSeries(
      label: 'Composite',
      color: DashboardColors.cpu,
      fillColor: DashboardColors.cpuFill,
      spots: buildSpots((summary) => summary.overallTemperature),
    ),
    _TrendSeries(
      label: 'CPU Avg',
      color: DashboardColors.info,
      spots: buildSpots((summary) => summary.cpuAverage),
    ),
    _TrendSeries(
      label: 'GPU Avg',
      color: DashboardColors.gpu,
      spots: buildSpots((summary) => summary.gpuAverage),
    ),
  ];
}

double _trendMinY(List<_TrendSeries> series) {
  final values = [
    for (final item in series) ...item.spots.map((spot) => spot.y),
  ];
  if (values.isEmpty) {
    return 0;
  }
  final minimum = values.reduce(math.min);
  return math.max(0, (minimum - 2).floorToDouble());
}

double _trendMaxY(List<_TrendSeries> series) {
  final values = [
    for (final item in series) ...item.spots.map((spot) => spot.y),
  ];
  if (values.isEmpty) {
    return 100;
  }
  final maximum = values.reduce(math.max);
  return (maximum + 2).ceilToDouble();
}

double _trendMaxX(List<_TrendSeries> series) {
  final values = [
    for (final item in series) ...item.spots.map((spot) => spot.x),
  ];
  if (values.isEmpty) {
    return 1;
  }
  return math.max(1, values.reduce(math.max));
}

double _trendInterval(List<_TrendSeries> series) {
  final span = (_trendMaxY(series) - _trendMinY(series)).abs();
  if (span <= 8) {
    return 2;
  }
  if (span <= 20) {
    return 5;
  }
  return 10;
}
