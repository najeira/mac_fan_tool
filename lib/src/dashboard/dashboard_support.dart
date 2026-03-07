import 'package:flutter/material.dart';

import 'package:mac_fan_tool/src/dashboard/dashboard_colors.dart';
import 'package:mac_fan_tool/src/hardware/hardware_models.dart';

import 'dashboard_summary.dart';

String? hardwareNote(MonitorState state) {
  return state.snapshot.note ?? state.capabilities.note ?? state.device.note;
}

Color thermalChipColor(ThermalStateData? level) {
  switch (level) {
    case ThermalStateData.nominal:
      return DashboardColors.thermalNominal;
    case ThermalStateData.fair:
      return DashboardColors.warning;
    case ThermalStateData.serious:
      return DashboardColors.alert;
    case ThermalStateData.critical:
      return DashboardColors.danger;
    case ThermalStateData.unknown:
    case null:
      return DashboardColors.neutralChip;
  }
}

String formatTemperature(double? value) {
  if (value == null) {
    return ' - ';
  }
  return '${value.toStringAsFixed(1)} °C';
}

String sensorCountCaption(int count, String category) {
  if (count <= 0) {
    return 'No $category channels available yet';
  }
  return '$count $category channel${count == 1 ? '' : 's'} aggregated';
}

String compactSensorCountLabel(int count) {
  if (count <= 0) {
    return '0 ch';
  }
  return '$count ch';
}

String sampleAge(DateTime capturedAt) {
  if (capturedAt.millisecondsSinceEpoch == 0) {
    return 'Pending';
  }

  final age = DateTime.now().difference(capturedAt);
  if (age.inSeconds < 60) {
    return '${age.inSeconds}s ago';
  }
  if (age.inMinutes < 60) {
    return '${age.inMinutes}m ago';
  }
  return '${age.inHours}h ago';
}

String formatSampleTime(DateTime capturedAt) {
  if (capturedAt.millisecondsSinceEpoch == 0) {
    return 'not sampled yet';
  }

  final hour = capturedAt.hour.toString().padLeft(2, '0');
  final minute = capturedAt.minute.toString().padLeft(2, '0');
  final second = capturedAt.second.toString().padLeft(2, '0');
  return '$hour:$minute:$second';
}

String formatFanSummary(FanSummary? summary) {
  if (summary == null) {
    return ' - ';
  }
  if (summary.fanCount == 1) {
    return '${summary.averageRpm} rpm';
  }
  return '${summary.averageRpm} RPM AVG ${summary.fanCount}';
}

Color fanSummaryChipColor(FanSummary? summary) {
  final normalizedSpeed = summary?.normalizedSpeed;
  if (normalizedSpeed == null) {
    return DashboardColors.neutralChip;
  }

  if (normalizedSpeed < 0.35) {
    return DashboardColors.fanAutomatic;
  }
  if (normalizedSpeed < 0.65) {
    return DashboardColors.warning;
  }
  if (normalizedSpeed < 0.85) {
    return DashboardColors.alert;
  }
  return DashboardColors.danger;
}

Color sensorColor(SensorKindData? kind) {
  switch (kind) {
    case SensorKindData.cpu:
      return DashboardColors.cpu;
    case SensorKindData.gpu:
      return DashboardColors.gpu;
    case SensorKindData.memory:
      return DashboardColors.memory;
    case SensorKindData.ambient:
      return DashboardColors.ambient;
    case SensorKindData.other:
    case null:
      return DashboardColors.otherSensor;
  }
}

List<SensorReadingData> cpuSensors(List<SensorReadingData> sensors) {
  return [
    for (final sensor in sensors)
      if (sensor.normalizedKind == SensorKindData.cpu) sensor,
  ];
}

List<SensorReadingData> gpuSensors(List<SensorReadingData> sensors) {
  return [
    for (final sensor in sensors)
      if (sensor.normalizedKind == SensorKindData.gpu) sensor,
  ];
}

List<SensorReadingData> memorySensors(List<SensorReadingData> sensors) {
  return [
    for (final sensor in sensors)
      if (sensor.normalizedKind == SensorKindData.memory) sensor,
  ];
}

List<SensorReadingData> ambientSensors(List<SensorReadingData> sensors) {
  return [
    for (final sensor in sensors)
      if (sensor.normalizedKind == SensorKindData.ambient) sensor,
  ];
}

List<SensorReadingData> diskSensors(List<SensorReadingData> sensors) {
  return [
    for (final sensor in sensors)
      if (_matchesCategory(sensor, const ['ssd', 'nand', 'disk'])) sensor,
  ];
}

List<SensorReadingData> powerSensors(List<SensorReadingData> sensors) {
  return [
    for (final sensor in sensors)
      if (sensor.normalizedKind == SensorKindData.other &&
          _matchesCategory(sensor, const [
            'power',
            'supply',
            'pmgr',
            'manager',
            'pmu',
            'calibration',
          ]))
        sensor,
  ];
}

List<SensorReadingData> supportingSensors(List<SensorReadingData> sensors) {
  final cpuIds = cpuSensors(sensors).map((sensor) => sensor.stableId).toSet();
  final gpuIds = gpuSensors(sensors).map((sensor) => sensor.stableId).toSet();

  return [
    for (final sensor in sensors)
      if (!cpuIds.contains(sensor.stableId) &&
          !gpuIds.contains(sensor.stableId))
        sensor,
  ];
}

double? mean(Iterable<double> values) {
  final list = values.where((value) => value.isFinite).toList();
  if (list.isEmpty) {
    return null;
  }
  return list.reduce((a, b) => a + b) / list.length;
}

bool _matchesCategory(SensorReadingData sensor, List<String> keywords) {
  final text = '${sensor.displayName} ${sensor.stableId}'.toLowerCase();
  for (final keyword in keywords) {
    if (text.contains(keyword)) {
      return true;
    }
  }
  return false;
}
