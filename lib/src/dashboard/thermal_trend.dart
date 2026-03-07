import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:mac_fan_tool/src/dashboard/dashboard_colors.dart';
import 'package:mac_fan_tool/src/dashboard/dashboard_summary.dart';
import 'package:mac_fan_tool/src/hardware/hardware_models.dart';

class ThermalTrendModel {
  const ThermalTrendModel({
    required this.series,
    required this.minY,
    required this.maxY,
    required this.maxX,
    required this.interval,
  });

  factory ThermalTrendModel.fromHistory(List<HardwareSnapshotData> history) {
    final summaries = history
        .map((snapshot) => DashboardSummary.fromSnapshot(snapshot))
        .toList();
    final series = _buildSeries(summaries);

    return ThermalTrendModel(
      series: series,
      minY: _minY(series),
      maxY: _maxY(series),
      maxX: _maxX(series),
      interval: _interval(series),
    );
  }

  final List<ThermalTrendSeries> series;
  final double minY;
  final double maxY;
  final double maxX;
  final double interval;

  bool get isEmpty => series.every((item) => item.points.length < 2);

  List<ThermalTrendSeries> get visibleSeries {
    return [
      for (final item in series)
        if (item.points.isNotEmpty) item,
    ];
  }
}

class ThermalTrendSeries {
  const ThermalTrendSeries({
    required this.label,
    required this.color,
    required this.points,
    this.fillColor,
  });

  final String label;
  final Color color;
  final List<ThermalTrendPoint> points;
  final Color? fillColor;
}

class ThermalTrendPoint {
  const ThermalTrendPoint({required this.x, required this.y});

  final double x;
  final double y;
}

List<ThermalTrendSeries> _buildSeries(List<DashboardSummary> summaries) {
  List<ThermalTrendPoint> buildPoints(
    double? Function(DashboardSummary) selector,
  ) {
    final points = <ThermalTrendPoint>[];
    for (final entry in summaries.asMap().entries) {
      final value = selector(entry.value);
      if (value != null) {
        points.add(ThermalTrendPoint(x: entry.key.toDouble(), y: value));
      }
    }
    return points;
  }

  return [
    ThermalTrendSeries(
      label: 'Composite',
      color: DashboardColors.cpu,
      fillColor: DashboardColors.cpuFill,
      points: buildPoints((summary) => summary.overallTemperature),
    ),
    ThermalTrendSeries(
      label: 'CPU',
      color: DashboardColors.info,
      points: buildPoints((summary) => summary.cpuAverage),
    ),
    ThermalTrendSeries(
      label: 'GPU',
      color: DashboardColors.gpu,
      points: buildPoints((summary) => summary.gpuAverage),
    ),
    ThermalTrendSeries(
      label: 'Power',
      color: DashboardColors.power,
      points: buildPoints((summary) => summary.powerAverage),
    ),
    ThermalTrendSeries(
      label: 'Disk',
      color: DashboardColors.disk,
      points: buildPoints((summary) => summary.diskAverage),
    ),
    ThermalTrendSeries(
      label: 'Memory',
      color: DashboardColors.memory,
      points: buildPoints((summary) => summary.memoryAverage),
    ),
  ];
}

double _minY(List<ThermalTrendSeries> series) {
  final values = [
    for (final item in series) ...item.points.map((point) => point.y),
  ];
  if (values.isEmpty) {
    return 0;
  }

  final minimum = values.reduce(math.min);
  return math.max(0, (minimum - 2).floorToDouble());
}

double _maxY(List<ThermalTrendSeries> series) {
  final values = [
    for (final item in series) ...item.points.map((point) => point.y),
  ];
  if (values.isEmpty) {
    return 100;
  }

  final maximum = values.reduce(math.max);
  return (maximum + 2).ceilToDouble();
}

double _maxX(List<ThermalTrendSeries> series) {
  final values = [
    for (final item in series) ...item.points.map((point) => point.x),
  ];
  if (values.isEmpty) {
    return 1;
  }

  return math.max(1, values.reduce(math.max));
}

double _interval(List<ThermalTrendSeries> series) {
  final span = (_maxY(series) - _minY(series)).abs();
  if (span <= 8) {
    return 2;
  }
  if (span <= 20) {
    return 5;
  }
  return 10;
}
