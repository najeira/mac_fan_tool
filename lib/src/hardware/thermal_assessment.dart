import 'package:mac_fan_tool/src/hardware/hardware_models.dart';
import 'package:mac_fan_tool/src/hardware/sensor_groups.dart';

enum AppThermalLevel { unknown, cool, elevated, hot, critical }

class AppThermalAssessment {
  const AppThermalAssessment({
    required this.level,
    required this.macosState,
    required this.cpuAverage,
    required this.gpuAverage,
    required this.overallTemperature,
    required this.peakTemperature,
    required this.ambientAverage,
    required this.trendDelta,
    required this.isRisingFast,
  });

  const AppThermalAssessment.unknown({
    ThermalStateData macosState = ThermalStateData.unknown,
  }) : this(
         level: AppThermalLevel.unknown,
         macosState: macosState,
         cpuAverage: null,
         gpuAverage: null,
         overallTemperature: null,
         peakTemperature: null,
         ambientAverage: null,
         trendDelta: 0,
         isRisingFast: false,
       );

  final AppThermalLevel level;
  final ThermalStateData macosState;
  final double? cpuAverage;
  final double? gpuAverage;
  final double? overallTemperature;
  final double? peakTemperature;
  final double? ambientAverage;
  final double trendDelta;
  final bool isRisingFast;

  bool get hasTelemetry {
    return cpuAverage != null ||
        gpuAverage != null ||
        overallTemperature != null ||
        peakTemperature != null;
  }
}

AppThermalAssessment assessThermalState(
  HardwareSnapshotData snapshot, {
  List<HardwareSnapshotData> history = const <HardwareSnapshotData>[],
}) {
  final samples = <HardwareSnapshotData>[
    ...history,
    if (!_containsSnapshot(history, snapshot)) snapshot,
  ];
  final metrics = [
    for (final item in samples) _SnapshotThermalMetrics.fromSnapshot(item),
  ];
  if (metrics.isEmpty) {
    return AppThermalAssessment.unknown(macosState: snapshot.thermalLevel);
  }

  final current = metrics.last;
  if (!current.hasTelemetry) {
    return AppThermalAssessment.unknown(macosState: snapshot.thermalLevel);
  }

  var level = current.baseLevel;
  level = _maxLevel(level, _macosMinimum(snapshot.thermalLevel));

  final trendDelta = _trendDelta(metrics);
  final isRisingFast = trendDelta >= 8;
  if (isRisingFast && _canPromoteForTrend(current, level)) {
    level = _promote(level);
  }

  level = _applyCooldownHold(metrics, level);

  return AppThermalAssessment(
    level: level,
    macosState: snapshot.thermalLevel,
    cpuAverage: current.cpuAverage,
    gpuAverage: current.gpuAverage,
    overallTemperature: current.overallTemperature,
    peakTemperature: current.peakTemperature,
    ambientAverage: current.ambientAverage,
    trendDelta: trendDelta,
    isRisingFast: isRisingFast,
  );
}

class _SnapshotThermalMetrics {
  const _SnapshotThermalMetrics({
    required this.cpuAverage,
    required this.gpuAverage,
    required this.overallTemperature,
    required this.peakTemperature,
    required this.ambientAverage,
    required this.baseLevel,
  });

  factory _SnapshotThermalMetrics.fromSnapshot(HardwareSnapshotData snapshot) {
    final sensors = snapshot.sensorReadings;
    final all = [
      for (final sensor in sensors)
        if (sensor.numericValue.isFinite) sensor.numericValue,
    ];

    final cpuAverage = mean(
      cpuSensors(sensors).map((sensor) => sensor.numericValue),
    );
    final gpuAverage = mean(
      gpuSensors(sensors).map((sensor) => sensor.numericValue),
    );
    final memoryAverage = mean(
      memorySensors(sensors).map((sensor) => sensor.numericValue),
    );
    final ambientAverage = mean(
      ambientSensors(sensors).map((sensor) => sensor.numericValue),
    );
    final diskAverage = mean(
      diskSensors(sensors).map((sensor) => sensor.numericValue),
    );
    final powerAverage = mean(
      powerSensors(sensors).map((sensor) => sensor.numericValue),
    );
    final categoryAverages = [
      cpuAverage,
      gpuAverage,
      powerAverage,
      diskAverage,
      memoryAverage,
      ambientAverage,
    ].whereType<double>();
    final overallTemperature = mean(categoryAverages);
    final fallbackOverall = overallTemperature ?? mean(all);
    final peakTemperature = all.isEmpty ? null : all.reduce(_max);

    return _SnapshotThermalMetrics(
      cpuAverage: cpuAverage,
      gpuAverage: gpuAverage,
      overallTemperature: fallbackOverall,
      peakTemperature: peakTemperature,
      ambientAverage: ambientAverage,
      baseLevel: _deriveBaseLevel(
        cpuAverage: cpuAverage,
        gpuAverage: gpuAverage,
        overallTemperature: fallbackOverall,
        peakTemperature: peakTemperature,
      ),
    );
  }

  final double? cpuAverage;
  final double? gpuAverage;
  final double? overallTemperature;
  final double? peakTemperature;
  final double? ambientAverage;
  final AppThermalLevel baseLevel;

  bool get hasTelemetry {
    return cpuAverage != null ||
        gpuAverage != null ||
        overallTemperature != null ||
        peakTemperature != null;
  }
}

AppThermalLevel _deriveBaseLevel({
  required double? cpuAverage,
  required double? gpuAverage,
  required double? overallTemperature,
  required double? peakTemperature,
}) {
  if ([
    cpuAverage,
    gpuAverage,
    overallTemperature,
    peakTemperature,
  ].every((value) => value == null)) {
    return AppThermalLevel.unknown;
  }

  if (_isAtLeast(
    cpuAverage: cpuAverage,
    gpuAverage: gpuAverage,
    overallTemperature: overallTemperature,
    peakTemperature: peakTemperature,
    cpuOrGpuThreshold: 85,
    overallThreshold: 83,
    peakThreshold: 95,
  )) {
    return AppThermalLevel.critical;
  }

  if (_isAtLeast(
    cpuAverage: cpuAverage,
    gpuAverage: gpuAverage,
    overallTemperature: overallTemperature,
    peakTemperature: peakTemperature,
    cpuOrGpuThreshold: 75,
    overallThreshold: 72,
    peakThreshold: 85,
  )) {
    return AppThermalLevel.hot;
  }

  if (_isAtLeast(
    cpuAverage: cpuAverage,
    gpuAverage: gpuAverage,
    overallTemperature: overallTemperature,
    peakTemperature: peakTemperature,
    cpuOrGpuThreshold: 60,
    overallThreshold: 58,
    peakThreshold: 70,
  )) {
    return AppThermalLevel.elevated;
  }

  return AppThermalLevel.cool;
}

bool _isAtLeast({
  required double? cpuAverage,
  required double? gpuAverage,
  required double? overallTemperature,
  required double? peakTemperature,
  required double cpuOrGpuThreshold,
  required double overallThreshold,
  required double peakThreshold,
}) {
  return (cpuAverage != null && cpuAverage >= cpuOrGpuThreshold) ||
      (gpuAverage != null && gpuAverage >= cpuOrGpuThreshold) ||
      (overallTemperature != null && overallTemperature >= overallThreshold) ||
      (peakTemperature != null && peakTemperature >= peakThreshold);
}

AppThermalLevel _macosMinimum(ThermalStateData macosState) {
  switch (macosState) {
    case ThermalStateData.fair:
      return AppThermalLevel.elevated;
    case ThermalStateData.serious:
      return AppThermalLevel.hot;
    case ThermalStateData.critical:
      return AppThermalLevel.critical;
    case ThermalStateData.nominal:
    case ThermalStateData.unknown:
      return AppThermalLevel.unknown;
  }
}

double _trendDelta(List<_SnapshotThermalMetrics> metrics) {
  if (metrics.length < 2) {
    return 0;
  }

  final current = metrics.last;
  final windowStart = metrics.length > 15 ? metrics.length - 15 : 0;
  final previous = metrics[windowStart];
  final currentAnchor = current.peakTemperature ?? current.overallTemperature;
  final previousAnchor =
      previous.peakTemperature ?? previous.overallTemperature;
  if (currentAnchor == null || previousAnchor == null) {
    return 0;
  }
  return currentAnchor - previousAnchor;
}

bool _canPromoteForTrend(
  _SnapshotThermalMetrics current,
  AppThermalLevel level,
) {
  if (level == AppThermalLevel.critical || level == AppThermalLevel.unknown) {
    return false;
  }

  final anchor = current.peakTemperature ?? current.overallTemperature;
  return anchor != null && anchor >= 75;
}

AppThermalLevel _applyCooldownHold(
  List<_SnapshotThermalMetrics> metrics,
  AppThermalLevel currentLevel,
) {
  if (metrics.length < 2 || currentLevel == AppThermalLevel.critical) {
    return currentLevel;
  }

  final recentStart = metrics.length > 15 ? metrics.length - 15 : 0;
  final recentLevels = [
    for (final item in metrics.skip(recentStart)) item.baseLevel,
  ];
  final recentMax = recentLevels.fold<AppThermalLevel>(
    AppThermalLevel.unknown,
    _maxLevel,
  );
  if (_severity(recentMax) <= _severity(currentLevel)) {
    return currentLevel;
  }

  final current = metrics.last;
  if (_meetsCooldownThreshold(current, recentMax)) {
    return currentLevel;
  }
  return recentMax;
}

bool _meetsCooldownThreshold(
  _SnapshotThermalMetrics current,
  AppThermalLevel heldLevel,
) {
  final peak = current.peakTemperature;
  final cpuAverage = current.cpuAverage;
  final gpuAverage = current.gpuAverage;
  final overall = current.overallTemperature;

  switch (heldLevel) {
    case AppThermalLevel.critical:
      return _isBelowAll(
        peak: peak,
        cpuAverage: cpuAverage,
        gpuAverage: gpuAverage,
        overall: overall,
        peakThreshold: 88,
        cpuOrGpuThreshold: 80,
        overallThreshold: 78,
      );
    case AppThermalLevel.hot:
      return _isBelowAll(
        peak: peak,
        cpuAverage: cpuAverage,
        gpuAverage: gpuAverage,
        overall: overall,
        peakThreshold: 78,
        cpuOrGpuThreshold: 68,
        overallThreshold: 64,
      );
    case AppThermalLevel.elevated:
      return _isBelowAll(
        peak: peak,
        cpuAverage: cpuAverage,
        gpuAverage: gpuAverage,
        overall: overall,
        peakThreshold: 66,
        cpuOrGpuThreshold: 58,
        overallThreshold: 55,
      );
    case AppThermalLevel.cool:
    case AppThermalLevel.unknown:
      return true;
  }
}

bool _isBelowAll({
  required double? peak,
  required double? cpuAverage,
  required double? gpuAverage,
  required double? overall,
  required double peakThreshold,
  required double cpuOrGpuThreshold,
  required double overallThreshold,
}) {
  return (peak == null || peak < peakThreshold) &&
      (cpuAverage == null || cpuAverage < cpuOrGpuThreshold) &&
      (gpuAverage == null || gpuAverage < cpuOrGpuThreshold) &&
      (overall == null || overall < overallThreshold);
}

bool _containsSnapshot(
  List<HardwareSnapshotData> history,
  HardwareSnapshotData snapshot,
) {
  final capturedAt = snapshot.capturedAtEpochMs;
  if (capturedAt == null) {
    return false;
  }
  return history.any((item) => item.capturedAtEpochMs == capturedAt);
}

double _max(double left, double right) => left > right ? left : right;

int _severity(AppThermalLevel level) {
  switch (level) {
    case AppThermalLevel.unknown:
      return 0;
    case AppThermalLevel.cool:
      return 1;
    case AppThermalLevel.elevated:
      return 2;
    case AppThermalLevel.hot:
      return 3;
    case AppThermalLevel.critical:
      return 4;
  }
}

AppThermalLevel _promote(AppThermalLevel level) {
  switch (level) {
    case AppThermalLevel.unknown:
      return AppThermalLevel.unknown;
    case AppThermalLevel.cool:
      return AppThermalLevel.elevated;
    case AppThermalLevel.elevated:
      return AppThermalLevel.hot;
    case AppThermalLevel.hot:
    case AppThermalLevel.critical:
      return AppThermalLevel.critical;
  }
}

AppThermalLevel _maxLevel(AppThermalLevel left, AppThermalLevel right) {
  return _severity(left) >= _severity(right) ? left : right;
}
