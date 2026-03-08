import 'package:flutter_test/flutter_test.dart';

import 'package:mac_fan_tool/src/hardware/hardware_models.dart';
import 'package:mac_fan_tool/src/hardware/thermal_assessment.dart';

void main() {
  test('classifies high temperatures as hot even when macOS stays nominal', () {
    final assessment = assessThermalState(
      _snapshot(
        capturedAtEpochMs: 1,
        thermalState: ThermalStateData.nominal,
        sensors: [
          _sensor('cpu-1', 'CPU 1', 82, SensorKindData.cpu),
          _sensor('gpu-1', 'GPU 1', 78, SensorKindData.gpu),
          _sensor('ambient-1', 'Ambient 1', 31, SensorKindData.ambient),
        ],
      ),
    );

    expect(assessment.level, AppThermalLevel.hot);
  });

  test('raises the minimum level when macOS reports serious pressure', () {
    final assessment = assessThermalState(
      _snapshot(
        capturedAtEpochMs: 1,
        thermalState: ThermalStateData.serious,
        sensors: [
          _sensor('cpu-1', 'CPU 1', 53, SensorKindData.cpu),
          _sensor('ambient-1', 'Ambient 1', 29, SensorKindData.ambient),
        ],
      ),
    );

    expect(assessment.level, AppThermalLevel.hot);
  });

  test('promotes one level when temperatures are rising quickly', () {
    final history = [
      _snapshot(
        capturedAtEpochMs: 1,
        thermalState: ThermalStateData.nominal,
        sensors: [
          _sensor('cpu-1', 'CPU 1', 63, SensorKindData.cpu),
          _sensor('ambient-1', 'Ambient 1', 28, SensorKindData.ambient),
        ],
      ),
      _snapshot(
        capturedAtEpochMs: 2,
        thermalState: ThermalStateData.nominal,
        sensors: [
          _sensor('cpu-1', 'CPU 1', 74, SensorKindData.cpu),
          _sensor('power-1', 'Power Manager', 75, SensorKindData.other),
          _sensor('ambient-1', 'Ambient 1', 29, SensorKindData.ambient),
        ],
      ),
    ];

    final assessment = assessThermalState(history.last, history: history);

    expect(assessment.isRisingFast, isTrue);
    expect(assessment.level, AppThermalLevel.hot);
  });

  test('holds a hot state briefly until telemetry cools down enough', () {
    final history = [
      _snapshot(
        capturedAtEpochMs: 1,
        thermalState: ThermalStateData.nominal,
        sensors: [
          _sensor('cpu-1', 'CPU 1', 80, SensorKindData.cpu),
          _sensor('ambient-1', 'Ambient 1', 30, SensorKindData.ambient),
        ],
      ),
      _snapshot(
        capturedAtEpochMs: 2,
        thermalState: ThermalStateData.nominal,
        sensors: [
          _sensor('cpu-1', 'CPU 1', 69, SensorKindData.cpu),
          _sensor('ambient-1', 'Ambient 1', 30, SensorKindData.ambient),
        ],
      ),
    ];

    final assessment = assessThermalState(history.last, history: history);

    expect(assessment.level, AppThermalLevel.hot);
  });
}

HardwareSnapshotData _snapshot({
  required int capturedAtEpochMs,
  required ThermalStateData thermalState,
  required List<SensorReadingData> sensors,
}) {
  return HardwareSnapshotData(
    capturedAtEpochMs: capturedAtEpochMs,
    thermalState: thermalState,
    sensors: List<SensorReadingData>.unmodifiable(sensors),
    fans: const <FanReadingData>[],
  );
}

SensorReadingData _sensor(
  String id,
  String name,
  double value,
  SensorKindData kind,
) {
  return SensorReadingData(
    id: id,
    name: name,
    unit: 'C',
    value: value,
    kind: kind,
  );
}
