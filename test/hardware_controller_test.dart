import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mac_fan_tool/src/dashboard/dashboard_state.dart';
import 'package:mac_fan_tool/src/hardware/hardware_controller.dart';
import 'package:mac_fan_tool/src/hardware/hardware_models.dart';
import 'package:mac_fan_tool/src/hardware/hardware_repository.dart';

void main() {
  test('fan command notices auto-dismiss after their lifetime', () async {
    final repository = _FakeHardwareRepository(
      snapshots: [_sampleSnapshot(), _sampleSnapshot()],
      setFanModeError: StateError('native write failed'),
    );
    final container = ProviderContainer(
      overrides: [
        hardwareRepositoryProvider.overrideWithValue(repository),
        transientNoticeDurationProvider.overrideWithValue(
          const Duration(milliseconds: 10),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(monitorControllerProvider);
    await _waitForBootstrap(container);

    final controller = container.read(monitorControllerProvider.notifier);
    final fan = container.read(monitorSnapshotProvider).fanReadings.single;

    await controller.setFanTargetRpm(fan, 2400);

    final notice = container.read(monitorTransientNoticeProvider);
    expect(notice?.tone, MonitorNoticeTone.error);
    expect(
      notice?.message,
      'Fan command failed: Bad state: native write failed',
    );

    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(container.read(monitorTransientNoticeProvider), isNull);
  });
}

Future<void> _waitForBootstrap(ProviderContainer container) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    await Future<void>.delayed(Duration.zero);
    if (!container.read(monitorControllerProvider).isBootstrapping) {
      return;
    }
  }

  fail('MonitorController bootstrap did not finish in time.');
}

HardwareSnapshotData _sampleSnapshot() {
  return HardwareSnapshotData(
    capturedAtEpochMs: 1,
    thermalState: ThermalStateData.nominal,
    sensors: <SensorReadingData>[],
    fans: [
      FanReadingData(
        id: 'fan-0',
        name: 'System fan',
        currentRpm: 2100,
        minimumRpm: 1200,
        maximumRpm: 4200,
        targetRpm: 2100,
        mode: FanModeData.automatic,
      ),
    ],
  );
}

class _FakeHardwareRepository extends HardwareRepository {
  _FakeHardwareRepository({required this.snapshots, this.setFanModeError});

  final List<HardwareSnapshotData> snapshots;
  final Object? setFanModeError;
  var _snapshotIndex = 0;

  @override
  Future<DeviceMetadata> loadDeviceMetadata() async {
    return const DeviceMetadata(
      computerName: 'Test Mac',
      model: 'Mac16,7',
      architecture: 'arm64',
      osVersion: '15.0',
    );
  }

  @override
  Future<HardwareCapabilitiesData> loadCapabilities() async {
    return HardwareCapabilitiesData(
      supportsRawSensors: true,
      supportsFanControl: true,
      hasFans: true,
      backend: 'fake',
    );
  }

  @override
  Future<HardwareSnapshotData> loadSnapshot() async {
    final index = _snapshotIndex < snapshots.length
        ? _snapshotIndex
        : snapshots.length - 1;
    _snapshotIndex += 1;
    return snapshots[index];
  }

  @override
  Future<void> setFanMode(String fanId, FanModeData mode) async {
    if (setFanModeError != null) {
      throw setFanModeError!;
    }
  }

  @override
  Future<void> setFanTargetRpm(String fanId, int targetRpm) async {}
}
