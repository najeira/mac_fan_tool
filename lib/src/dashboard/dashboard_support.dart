import 'package:flutter/material.dart';

import 'package:mac_fan_tool/src/dashboard/dashboard_colors.dart';
import 'package:mac_fan_tool/src/hardware/hardware_models.dart';
export 'package:mac_fan_tool/src/hardware/sensor_groups.dart'
    show
        ambientSensors,
        cpuSensors,
        diskSensors,
        gpuSensors,
        mean,
        memorySensors,
        powerSensors,
        supportingSensors;
import 'package:mac_fan_tool/src/hardware/thermal_assessment.dart';

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

Color appThermalChipColor(AppThermalLevel level) {
  switch (level) {
    case AppThermalLevel.cool:
      return DashboardColors.thermalNominal;
    case AppThermalLevel.elevated:
      return DashboardColors.warning;
    case AppThermalLevel.hot:
      return DashboardColors.alert;
    case AppThermalLevel.critical:
      return DashboardColors.danger;
    case AppThermalLevel.unknown:
      return DashboardColors.neutralChip;
  }
}

String appThermalLabel(AppThermalLevel level) {
  switch (level) {
    case AppThermalLevel.cool:
      return 'Cool';
    case AppThermalLevel.elevated:
      return 'Elevated';
    case AppThermalLevel.hot:
      return 'Hot';
    case AppThermalLevel.critical:
      return 'Critical';
    case AppThermalLevel.unknown:
      return 'Unknown';
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
