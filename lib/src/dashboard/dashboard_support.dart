import 'package:flutter/material.dart';

import 'package:mac_fan_tool/src/hardware/hardware_models.dart';

String? hardwareNote(MonitorState state) {
  return state.snapshot.note ?? state.capabilities.note ?? state.device.note;
}

String thermalLabel(ThermalStateData? level) {
  switch (level) {
    case ThermalStateData.nominal:
      return 'Thermal nominal';
    case ThermalStateData.fair:
      return 'Thermal fair';
    case ThermalStateData.serious:
      return 'Thermal serious';
    case ThermalStateData.critical:
      return 'Thermal critical';
    case ThermalStateData.unknown:
    case null:
      return 'Thermal unknown';
  }
}

Color thermalChipColor(ThermalStateData? level) {
  switch (level) {
    case ThermalStateData.nominal:
      return const Color(0xFF1E6A5C);
    case ThermalStateData.fair:
      return const Color(0xFF866225);
    case ThermalStateData.serious:
      return const Color(0xFF9B5B26);
    case ThermalStateData.critical:
      return const Color(0xFF8F3F3D);
    case ThermalStateData.unknown:
    case null:
      return const Color(0xFF4B5D66);
  }
}

String compositeChipLabel(double? overallTemperature) {
  if (overallTemperature == null) {
    return '...';
  }
  return formatTemperature(overallTemperature);
}

String formatTemperature(double? value) {
  if (value == null) {
    return 'Unavailable';
  }
  return '${value.toStringAsFixed(1)} °C';
}

String sensorCountCaption(int count, String category) {
  if (count <= 0) {
    return 'No $category channels available yet';
  }
  return '$count $category channel${count == 1 ? '' : 's'} aggregated';
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

Color sensorColor(SensorKindData? kind) {
  switch (kind) {
    case SensorKindData.cpu:
      return const Color(0xFF2C8C7A);
    case SensorKindData.gpu:
      return const Color(0xFF9B5B26);
    case SensorKindData.memory:
      return const Color(0xFF5D6AC3);
    case SensorKindData.ambient:
      return const Color(0xFF6A6B3F);
    case SensorKindData.other:
    case null:
      return const Color(0xFF5D7078);
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
