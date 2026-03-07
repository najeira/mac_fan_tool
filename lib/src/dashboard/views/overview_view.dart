import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:mac_fan_tool/src/dashboard/dashboard_summary.dart';
import 'package:mac_fan_tool/src/dashboard/dashboard_support.dart';
import 'package:mac_fan_tool/src/dashboard/widgets/dashboard_common.dart';
import 'package:mac_fan_tool/src/hardware/hardware_models.dart';

class OverviewView extends StatelessWidget {
  const OverviewView({
    super.key,
    required this.state,
    required this.summary,
    required this.isWide,
  });

  final MonitorState state;
  final DashboardSummary summary;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final cards = [
      MetricCard(
        label: 'CPU Avg',
        value: formatTemperature(summary.cpuAverage),
        caption: sensorCountCaption(summary.cpuSensorCount, 'CPU'),
      ),
      MetricCard(
        label: 'GPU Avg',
        value: formatTemperature(summary.gpuAverage),
        caption: sensorCountCaption(summary.gpuSensorCount, 'GPU'),
      ),
      MetricCard(
        label: 'Power Avg',
        value: formatTemperature(summary.powerAverage),
        caption: sensorCountCaption(summary.powerSensorCount, 'power'),
      ),
      MetricCard(
        label: 'Disk Avg',
        value: formatTemperature(summary.diskAverage),
        caption: sensorCountCaption(summary.diskSensorCount, 'disk'),
      ),
      MetricCard(
        label: 'Memory Avg',
        value: formatTemperature(summary.memoryAverage),
        caption: sensorCountCaption(summary.memorySensorCount, 'memory'),
      ),
      MetricCard(
        label: 'Last Sample',
        value: sampleAge(state.snapshot.capturedAt),
        caption: 'Updated ${formatSampleTime(state.snapshot.capturedAt)}',
      ),
    ];

    final trendPanel = _ThermalTrendPanel(state: state);
    final breakdownPanel = _CategoryBreakdownPanel(summary: summary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 16, runSpacing: 16, children: cards),
        const SizedBox(height: 24),
        if (isWide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: trendPanel),
              const SizedBox(width: 20),
              Expanded(child: breakdownPanel),
            ],
          )
        else ...[
          trendPanel,
          const SizedBox(height: 20),
          breakdownPanel,
        ],
      ],
    );
  }
}

class _ThermalTrendPanel extends StatelessWidget {
  const _ThermalTrendPanel({required this.state});

  final MonitorState state;

  @override
  Widget build(BuildContext context) {
    final summaries = [
      for (final snapshot in state.history)
        DashboardSummary.fromSnapshot(snapshot),
    ];
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
                          color: Color(0x22354B55),
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
                                    ?.copyWith(color: const Color(0xFF50636A)),
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

class _CategoryBreakdownPanel extends StatelessWidget {
  const _CategoryBreakdownPanel({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final categories = [
      _SummaryCategory(
        label: 'CPU',
        value: summary.cpuAverage,
        count: summary.cpuSensorCount,
        color: sensorColor(SensorKind.cpu),
      ),
      _SummaryCategory(
        label: 'GPU',
        value: summary.gpuAverage,
        count: summary.gpuSensorCount,
        color: sensorColor(SensorKind.gpu),
      ),
      _SummaryCategory(
        label: 'Power',
        value: summary.powerAverage,
        count: summary.powerSensorCount,
        color: const Color(0xFF7A5B34),
      ),
      _SummaryCategory(
        label: 'Disk',
        value: summary.diskAverage,
        count: summary.diskSensorCount,
        color: const Color(0xFF546A36),
      ),
      _SummaryCategory(
        label: 'Memory',
        value: summary.memoryAverage,
        count: summary.memorySensorCount,
        color: sensorColor(SensorKind.memory),
      ),
      _SummaryCategory(
        label: 'Ambient',
        value: summary.ambientAverage,
        count: summary.ambientSensorCount,
        color: sensorColor(SensorKind.ambient),
      ),
    ];

    final maxValue = categories
        .map((category) => category.value ?? 0)
        .fold<double>(0, math.max);

    return SectionPanel(
      title: 'Category Snapshot',
      subtitle:
          'Balanced averages by thermal domain so one large sensor family does not dominate the overview.',
      child: Column(
        children: [
          for (final category in categories) ...[
            _CategoryBarRow(
              category: category,
              maxValue: maxValue <= 0 ? 1 : maxValue,
            ),
            if (category != categories.last) const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

class _CategoryBarRow extends StatelessWidget {
  const _CategoryBarRow({required this.category, required this.maxValue});

  final _SummaryCategory category;
  final double maxValue;

  @override
  Widget build(BuildContext context) {
    final ratio = category.value == null ? 0.0 : category.value! / maxValue;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 92,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                category.label,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                category.count <= 0
                    ? 'No sensors'
                    : '${category.count} sensors',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: const Color(0xFF61757D)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio.clamp(0, 1),
              minHeight: 12,
              backgroundColor: const Color(0xFFE7ECEE),
              color: category.color,
            ),
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 92,
          child: Text(
            formatTemperature(category.value),
            textAlign: TextAlign.end,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
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

class _SummaryCategory {
  const _SummaryCategory({
    required this.label,
    required this.value,
    required this.count,
    required this.color,
  });

  final String label;
  final double? value;
  final int count;
  final Color color;
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
      color: const Color(0xFF2C8C7A),
      fillColor: const Color(0x222C8C7A),
      spots: buildSpots((summary) => summary.overallTemperature),
    ),
    _TrendSeries(
      label: 'CPU Avg',
      color: const Color(0xFF265C6A),
      spots: buildSpots((summary) => summary.cpuAverage),
    ),
    _TrendSeries(
      label: 'GPU Avg',
      color: const Color(0xFF9B5B26),
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
