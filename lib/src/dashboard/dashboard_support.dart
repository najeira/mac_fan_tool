import 'package:flutter/material.dart';

import 'package:mac_fan_tool/src/hardware/hardware_models.dart';

String? hardwareNote(MonitorState state) {
  return state.snapshot.note ?? state.capabilities.note ?? state.device.note;
}

String thermalLabel(ThermalStateLevel level) {
  switch (level) {
    case ThermalStateLevel.nominal:
      return 'Thermal nominal';
    case ThermalStateLevel.fair:
      return 'Thermal fair';
    case ThermalStateLevel.serious:
      return 'Thermal serious';
    case ThermalStateLevel.critical:
      return 'Thermal critical';
    case ThermalStateLevel.unknown:
      return 'Thermal unknown';
  }
}

Color thermalChipColor(ThermalStateLevel level) {
  switch (level) {
    case ThermalStateLevel.nominal:
      return const Color(0xFF1E6A5C);
    case ThermalStateLevel.fair:
      return const Color(0xFF866225);
    case ThermalStateLevel.serious:
      return const Color(0xFF9B5B26);
    case ThermalStateLevel.critical:
      return const Color(0xFF8F3F3D);
    case ThermalStateLevel.unknown:
      return const Color(0xFF4B5D66);
  }
}

String compositeChipLabel(double? overallTemperature) {
  if (overallTemperature == null) {
    return 'Composite pending';
  }
  return 'Composite ${overallTemperature.toStringAsFixed(1)} C';
}

String formatTemperature(double? value) {
  if (value == null) {
    return 'Unavailable';
  }
  return '${value.toStringAsFixed(1)} C';
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

Color sensorColor(SensorKind kind) {
  switch (kind) {
    case SensorKind.cpu:
      return const Color(0xFF2C8C7A);
    case SensorKind.gpu:
      return const Color(0xFF9B5B26);
    case SensorKind.memory:
      return const Color(0xFF5D6AC3);
    case SensorKind.ambient:
      return const Color(0xFF6A6B3F);
    case SensorKind.other:
      return const Color(0xFF5D7078);
  }
}

List<SensorReading> cpuSensors(List<SensorReading> sensors) {
  return [
    for (final sensor in sensors)
      if (sensor.kind == SensorKind.cpu) sensor,
  ];
}

List<SensorReading> gpuSensors(List<SensorReading> sensors) {
  return [
    for (final sensor in sensors)
      if (sensor.kind == SensorKind.gpu) sensor,
  ];
}

List<SensorReading> memorySensors(List<SensorReading> sensors) {
  return [
    for (final sensor in sensors)
      if (sensor.kind == SensorKind.memory) sensor,
  ];
}

List<SensorReading> ambientSensors(List<SensorReading> sensors) {
  return [
    for (final sensor in sensors)
      if (sensor.kind == SensorKind.ambient) sensor,
  ];
}

List<SensorReading> diskSensors(List<SensorReading> sensors) {
  return [
    for (final sensor in sensors)
      if (_matchesCategory(sensor, const ['ssd', 'nand', 'disk'])) sensor,
  ];
}

List<SensorReading> powerSensors(List<SensorReading> sensors) {
  return [
    for (final sensor in sensors)
      if (sensor.kind == SensorKind.other &&
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

List<SensorReading> supportingSensors(List<SensorReading> sensors) {
  final cpuIds = cpuSensors(sensors).map((sensor) => sensor.id).toSet();
  final gpuIds = gpuSensors(sensors).map((sensor) => sensor.id).toSet();

  return [
    for (final sensor in sensors)
      if (!cpuIds.contains(sensor.id) && !gpuIds.contains(sensor.id)) sensor,
  ];
}

double? mean(Iterable<double> values) {
  final list = values.where((value) => value.isFinite).toList();
  if (list.isEmpty) {
    return null;
  }
  return list.reduce((a, b) => a + b) / list.length;
}

bool _matchesCategory(SensorReading sensor, List<String> keywords) {
  final text = '${sensor.name} ${sensor.id}'.toLowerCase();
  for (final keyword in keywords) {
    if (text.contains(keyword)) {
      return true;
    }
  }
  return false;
}
