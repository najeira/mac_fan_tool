import 'package:flutter_test/flutter_test.dart';

import 'package:mac_fan_tool/src/dashboard/dashboard_support.dart';
import 'package:mac_fan_tool/src/hardware/hardware_models.dart';

void main() {
  test('cpuSensors sorts numeric suffixes naturally', () {
    final sensors = [
      SensorReadingData(
        id: 'cpu-10',
        name: 'CPU 10',
        unit: 'C',
        value: 50,
        kind: SensorKindData.cpu,
      ),
      SensorReadingData(
        id: 'cpu-2',
        name: 'CPU 2',
        unit: 'C',
        value: 48,
        kind: SensorKindData.cpu,
      ),
      SensorReadingData(
        id: 'cpu-1',
        name: 'CPU 1',
        unit: 'C',
        value: 47,
        kind: SensorKindData.cpu,
      ),
    ];

    final result = cpuSensors(sensors);

    expect(result.map((sensor) => sensor.displayName).toList(), [
      'CPU 1',
      'CPU 2',
      'CPU 10',
    ]);
  });
}
