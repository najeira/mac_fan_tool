import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mac_fan_tool/src/dashboard/dashboard_state.dart';
import 'package:mac_fan_tool/src/hardware/hardware_models.dart';

void main() {
  test('sensorReadings getter returns the same list instance', () {
    final snapshot = _snapshot(cpuTemperature: 48);

    expect(identical(snapshot.sensorReadings, snapshot.sensorReadings), isTrue);
  });

  test(
    'cpu sensor provider does not notify when derived readings are unchanged',
    () async {
      final snapshotProvider =
          NotifierProvider<_SnapshotNotifier, HardwareSnapshotData>(
            _SnapshotNotifier.new,
          );
      final container = ProviderContainer(
        overrides: [
          monitorSnapshotProvider.overrideWith(
            (ref) => ref.watch(snapshotProvider),
          ),
        ],
      );
      addTearDown(container.dispose);

      var notificationCount = 0;
      final subscription = container.listen(
        cpuSensorReadingsProvider,
        (previous, next) => notificationCount += 1,
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      container
          .read(snapshotProvider.notifier)
          .replace(_snapshot(cpuTemperature: 48));
      await Future<void>.delayed(Duration.zero);

      expect(notificationCount, 1);

      container
          .read(snapshotProvider.notifier)
          .replace(_snapshot(cpuTemperature: 52));
      await Future<void>.delayed(Duration.zero);

      expect(notificationCount, 2);
    },
  );
}

class _SnapshotNotifier extends Notifier<HardwareSnapshotData> {
  @override
  HardwareSnapshotData build() {
    return _snapshot(cpuTemperature: 48);
  }

  void replace(HardwareSnapshotData snapshot) {
    state = snapshot;
  }
}

HardwareSnapshotData _snapshot({required double cpuTemperature}) {
  return HardwareSnapshotData(
    capturedAtEpochMs: 1,
    thermalState: ThermalStateData.nominal,
    sensors: List<SensorReadingData>.unmodifiable([
      SensorReadingData(
        id: 'cpu-1',
        name: 'CPU 1',
        unit: 'C',
        value: cpuTemperature,
        kind: SensorKindData.cpu,
      ),
      SensorReadingData(
        id: 'ambient-1',
        name: 'Ambient 1',
        unit: 'C',
        value: 30,
        kind: SensorKindData.ambient,
      ),
    ]),
    fans: const <FanReadingData>[],
  );
}
