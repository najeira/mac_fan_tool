import 'dart:async';

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
      setFanTargetRpmError: StateError('native write failed'),
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

  test('setFanTargetRpm uses a single atomic repository command', () async {
    final repository = _FakeHardwareRepository(
      snapshots: [_sampleSnapshot(), _sampleSnapshot()],
    );
    final container = ProviderContainer(
      overrides: [hardwareRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    container.read(monitorControllerProvider);
    await _waitForBootstrap(container);

    final controller = container.read(monitorControllerProvider.notifier);
    final fan = container.read(monitorSnapshotProvider).fanReadings.single;

    await controller.setFanTargetRpm(fan, 2400);

    expect(repository.setFanModeCalls, isEmpty);
    expect(repository.setFanTargetRpmCalls, [('fan-0', 2400)]);
  });

  test('setFanTargetRpm shows success only after refresh completes', () async {
    final refreshCompleter = Completer<void>();
    final repository = _FakeHardwareRepository(
      snapshots: [_sampleSnapshot(), _sampleSnapshot()],
      loadSnapshotCompleters: {1: refreshCompleter},
    );
    final container = ProviderContainer(
      overrides: [hardwareRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    container.read(monitorControllerProvider);
    await _waitForBootstrap(container);

    final controller = container.read(monitorControllerProvider.notifier);
    final fan = container.read(monitorSnapshotProvider).fanReadings.single;

    final commandFuture = controller.setFanTargetRpm(fan, 2400);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(monitorTransientNoticeProvider), isNull);
    expect(
      container.read(monitorActiveFanCommandIdsProvider),
      contains('fan-0'),
    );

    refreshCompleter.complete();
    await commandFuture;

    final notice = container.read(monitorTransientNoticeProvider);
    expect(notice?.tone, MonitorNoticeTone.success);
    expect(notice?.message, 'System fan target set to 2400 RPM.');
    expect(container.read(monitorActiveFanCommandIdsProvider), isEmpty);
  });

  test(
    'setFanTargetRpm shows an info notice when refresh fails afterwards',
    () async {
      final repository = _FakeHardwareRepository(
        snapshots: [_sampleSnapshot(), _sampleSnapshot()],
        loadSnapshotErrors: {1: StateError('stale telemetry')},
      );
      final container = ProviderContainer(
        overrides: [hardwareRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      container.read(monitorControllerProvider);
      await _waitForBootstrap(container);

      final controller = container.read(monitorControllerProvider.notifier);
      final fan = container.read(monitorSnapshotProvider).fanReadings.single;

      await controller.setFanTargetRpm(fan, 2400);

      final notice = container.read(monitorTransientNoticeProvider);
      expect(notice?.tone, MonitorNoticeTone.info);
      expect(
        notice?.message,
        'System fan target set to 2400 RPM. Telemetry refresh failed, so the dashboard may be stale.',
      );
      expect(
        container.read(monitorErrorMessageProvider),
        'Telemetry refresh failed: Bad state: stale telemetry',
      );
    },
  );

  test('setFanTargetRpm starts manual lease heartbeats', () async {
    final repository = _FakeHardwareRepository(
      snapshots: [
        _sampleSnapshot(),
        _sampleSnapshot(mode: FanModeData.manual, targetRpm: 2400),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        hardwareRepositoryProvider.overrideWithValue(repository),
        manualLeaseHeartbeatIntervalProvider.overrideWithValue(
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
    await Future<void>.delayed(const Duration(milliseconds: 35));

    expect(repository.renewManualLeaseCalls, contains('fan-0'));
  });

  test(
    'setFanTargetRpm keeps manual lease heartbeats when telemetry still reads automatic',
    () async {
      final repository = _FakeHardwareRepository(
        snapshots: [
          _sampleSnapshot(),
          _sampleSnapshot(mode: FanModeData.automatic, targetRpm: 2400),
        ],
      );
      final container = ProviderContainer(
        overrides: [
          hardwareRepositoryProvider.overrideWithValue(repository),
          manualLeaseHeartbeatIntervalProvider.overrideWithValue(
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
      await Future<void>.delayed(const Duration(milliseconds: 35));

      expect(repository.renewManualLeaseCalls, contains('fan-0'));
    },
  );

  test('setFanAutomatic stops manual lease heartbeats', () async {
    final repository = _FakeHardwareRepository(
      snapshots: [
        _sampleSnapshot(),
        _sampleSnapshot(mode: FanModeData.manual, targetRpm: 2400),
        _sampleSnapshot(),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        hardwareRepositoryProvider.overrideWithValue(repository),
        manualLeaseHeartbeatIntervalProvider.overrideWithValue(
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
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final renewCallCountBeforeAutomatic =
        repository.renewManualLeaseCalls.length;

    await controller.setFanAutomatic(fan);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(
      repository.renewManualLeaseCalls.length,
      renewCallCountBeforeAutomatic,
    );
  });

  test('tracks multiple active fan commands independently', () async {
    final firstFanModeCompleter = Completer<void>();
    final secondFanModeCompleter = Completer<void>();
    final repository = _FakeHardwareRepository(
      snapshots: [
        _multiFanSnapshot(),
        _multiFanSnapshot(),
        _multiFanSnapshot(),
      ],
      setFanModeCompleters: {
        'fan-0': firstFanModeCompleter,
        'fan-1': secondFanModeCompleter,
      },
    );
    final container = ProviderContainer(
      overrides: [hardwareRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    container.read(monitorControllerProvider);
    await _waitForBootstrap(container);

    final controller = container.read(monitorControllerProvider.notifier);
    final fans = container.read(monitorSnapshotProvider).fanReadings;

    final firstCommand = controller.setFanAutomatic(fans[0]);
    final secondCommand = controller.setFanAutomatic(fans[1]);
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(monitorActiveFanCommandIdsProvider),
      containsAll(<String>{'fan-0', 'fan-1'}),
    );

    firstFanModeCompleter.complete();
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(monitorActiveFanCommandIdsProvider),
      contains('fan-1'),
    );
    expect(
      container.read(monitorActiveFanCommandIdsProvider),
      isNot(contains('fan-0')),
    );

    secondFanModeCompleter.complete();
    await Future.wait<void>([firstCommand, secondCommand]);

    expect(container.read(monitorActiveFanCommandIdsProvider), isEmpty);
  });

  test('refresh keeps the previous error until a refresh succeeds', () async {
    final successfulRefreshCompleter = Completer<void>();
    final repository = _FakeHardwareRepository(
      snapshots: [_sampleSnapshot(), _sampleSnapshot()],
      loadSnapshotErrors: {0: StateError('bridge unavailable')},
      loadSnapshotCompleters: {1: successfulRefreshCompleter},
    );
    final container = ProviderContainer(
      overrides: [hardwareRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    container.read(monitorControllerProvider);
    await _waitForBootstrap(container);

    expect(
      container.read(monitorErrorMessageProvider),
      'Telemetry refresh failed: Bad state: bridge unavailable',
    );

    final refreshFuture = container
        .read(monitorControllerProvider.notifier)
        .refresh();
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(monitorErrorMessageProvider),
      'Telemetry refresh failed: Bad state: bridge unavailable',
    );

    successfulRefreshCompleter.complete();
    await refreshFuture;

    expect(container.read(monitorErrorMessageProvider), isNull);
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

HardwareSnapshotData _sampleSnapshot({
  FanModeData mode = FanModeData.automatic,
  int targetRpm = 2100,
}) {
  return _sampleSnapshotWithMode(mode, targetRpm);
}

HardwareSnapshotData _sampleSnapshotWithMode(FanModeData mode, int targetRpm) {
  return HardwareSnapshotData(
    capturedAtEpochMs: 1,
    thermalState: ThermalStateData.nominal,
    sensors: const <SensorReadingData>[],
    fans: List<FanReadingData>.unmodifiable([
      FanReadingData(
        id: 'fan-0',
        name: 'System fan',
        currentRpm: 2100,
        minimumRpm: 1200,
        maximumRpm: 4200,
        targetRpm: targetRpm,
        mode: mode,
      ),
    ]),
  );
}

HardwareSnapshotData _multiFanSnapshot() {
  return HardwareSnapshotData(
    capturedAtEpochMs: 1,
    thermalState: ThermalStateData.nominal,
    sensors: const <SensorReadingData>[],
    fans: List<FanReadingData>.unmodifiable([
      FanReadingData(
        id: 'fan-0',
        name: 'Left fan',
        currentRpm: 2100,
        minimumRpm: 1200,
        maximumRpm: 4200,
        targetRpm: 2100,
        mode: FanModeData.automatic,
      ),
      FanReadingData(
        id: 'fan-1',
        name: 'Right fan',
        currentRpm: 2200,
        minimumRpm: 1200,
        maximumRpm: 4300,
        targetRpm: 2200,
        mode: FanModeData.automatic,
      ),
    ]),
  );
}

class _FakeHardwareRepository extends HardwareRepository {
  _FakeHardwareRepository({
    required this.snapshots,
    this.setFanTargetRpmError,
    this.setFanModeCompleters = const {},
    this.loadSnapshotErrors = const {},
    this.loadSnapshotCompleters = const {},
  });

  final List<HardwareSnapshotData> snapshots;
  final Object? setFanTargetRpmError;
  final Map<String, Completer<void>> setFanModeCompleters;
  final Map<int, Object> loadSnapshotErrors;
  final Map<int, Completer<void>> loadSnapshotCompleters;
  final List<String> setFanModeCalls = <String>[];
  final List<(String, int)> setFanTargetRpmCalls = <(String, int)>[];
  final List<String> renewManualLeaseCalls = <String>[];
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
    final callIndex = _snapshotIndex;
    _snapshotIndex += 1;

    final completer = loadSnapshotCompleters[callIndex];
    if (completer != null) {
      await completer.future;
    }

    final error = loadSnapshotErrors[callIndex];
    if (error != null) {
      throw error;
    }

    final index = callIndex < snapshots.length
        ? callIndex
        : snapshots.length - 1;
    return snapshots[index];
  }

  @override
  Future<void> setFanMode(String fanId, FanModeData mode) async {
    setFanModeCalls.add(fanId);
    final completer = setFanModeCompleters[fanId];
    if (completer != null) {
      await completer.future;
    }
  }

  @override
  Future<void> setFanTargetRpm(String fanId, int targetRpm) async {
    setFanTargetRpmCalls.add((fanId, targetRpm));
    if (setFanTargetRpmError != null) {
      throw setFanTargetRpmError!;
    }
  }

  @override
  Future<void> renewManualFanLease(String fanId) async {
    renewManualLeaseCalls.add(fanId);
  }
}
