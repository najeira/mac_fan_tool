import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';

import 'package:mac_fan_tool/src/hardware/hardware_models.dart';
import 'package:mac_fan_tool/src/pigeon/hardware_api.g.dart';

class HardwareRepository {
  HardwareRepository({HardwareHostApi? api, DeviceInfoPlugin? deviceInfoPlugin})
    : _api = api ?? HardwareHostApi(),
      _deviceInfoPlugin = deviceInfoPlugin ?? DeviceInfoPlugin();

  final HardwareHostApi _api;
  final DeviceInfoPlugin _deviceInfoPlugin;

  Future<DeviceMetadata> loadDeviceMetadata() async {
    return _loadWithFallback(
      load: () async {
        final info = await _deviceInfoPlugin.macOsInfo;

        return DeviceMetadata(
          computerName: info.computerName,
          model: info.model,
          architecture: info.arch,
          osVersion: info.osRelease,
        );
      },
      onMissingPlugin: () => const DeviceMetadata.unknown(
        note:
            'device_info_plus is not available in tests until plugin registration runs.',
      ),
      onPlatformError: (error) => DeviceMetadata.unknown(
        note: 'Device metadata is unavailable: ${error.message ?? error.code}',
      ),
      onUnknownError: (error) => DeviceMetadata.unknown(
        note: 'Device metadata is unavailable: $error',
      ),
    );
  }

  Future<HardwareCapabilitiesData> loadCapabilities() async {
    return _loadWithFallback(
      load: () async {
        final data = await _api.getCapabilities();
        return HardwareCapabilitiesData(
          supportsRawSensors: data.supportsRawSensors ?? false,
          supportsFanControl: data.supportsFanControl ?? false,
          hasFans: data.hasFans ?? false,
          backend: data.backend ?? 'native-bridge',
          note: data.note,
        );
      },
      onMissingPlugin: () => unavailableHardwareCapabilities(
        backend: 'pigeon-missing',
        note:
            'The native hardware bridge is not registered in this environment yet.',
      ),
      onPlatformError: (error) => unavailableHardwareCapabilities(
        backend: 'pigeon-error',
        note: 'Native capability probe failed: ${error.message ?? error.code}',
      ),
      onUnknownError: (error) => unavailableHardwareCapabilities(
        backend: 'pigeon-error',
        note: 'Native capability probe failed: $error',
      ),
    );
  }

  Future<HardwareSnapshotData> loadSnapshot() async {
    return _loadWithFallback(
      load: () async {
        final data = await _api.getSnapshot();

        return HardwareSnapshotData(
          capturedAtEpochMs:
              data.capturedAtEpochMs ?? DateTime.now().millisecondsSinceEpoch,
          thermalState: data.thermalState ?? ThermalStateData.unknown,
          sensors: _normalizeSensors(data.sensors),
          fans: _normalizeFans(data.fans),
          note: data.note,
        );
      },
      onMissingPlugin: () => emptyHardwareSnapshot(
        note:
            'The native hardware bridge is not registered in this environment yet.',
      ),
      onPlatformError: (error) => emptyHardwareSnapshot(
        note: 'Telemetry refresh failed: ${error.message ?? error.code}',
      ),
      onUnknownError: (error) =>
          emptyHardwareSnapshot(note: 'Telemetry refresh failed: $error'),
    );
  }

  Future<void> setFanMode(String fanId, FanModeData mode) async {
    await _runCommand(() => _api.setFanMode(fanId, mode));
  }

  Future<void> setFanTargetRpm(String fanId, int targetRpm) async {
    await _runCommand(() => _api.setFanTargetRpm(fanId, targetRpm));
  }

  Future<void> renewManualFanLease(String fanId) async {
    await _runCommand(() => _api.renewManualFanLease(fanId));
  }

  Future<T> _loadWithFallback<T>({
    required Future<T> Function() load,
    required T Function() onMissingPlugin,
    required T Function(PlatformException error) onPlatformError,
    required T Function(Object error) onUnknownError,
  }) async {
    try {
      return await load();
    } on MissingPluginException {
      return onMissingPlugin();
    } on PlatformException catch (error) {
      return onPlatformError(error);
    } catch (error) {
      return onUnknownError(error);
    }
  }

  Future<void> _runCommand(Future<void> Function() action) async {
    try {
      await action();
    } on PlatformException catch (error) {
      throw StateError(error.message ?? error.code);
    } catch (error) {
      throw StateError(error.toString());
    }
  }

  List<SensorReadingData> _normalizeSensors(List<SensorReadingData?>? sensors) {
    return List<SensorReadingData>.unmodifiable([
      for (final sensor in sensors ?? const <SensorReadingData?>[])
        if (sensor != null)
          SensorReadingData(
            id: sensor.stableId,
            name: sensor.displayName,
            unit: sensor.displayUnit,
            value: sensor.numericValue,
            kind: sensor.normalizedKind,
          ),
    ]);
  }

  List<FanReadingData> _normalizeFans(List<FanReadingData?>? fans) {
    return List<FanReadingData>.unmodifiable([
      for (final fan in fans ?? const <FanReadingData?>[])
        if (fan != null)
          FanReadingData(
            id: fan.stableId,
            name: fan.displayName,
            currentRpm: fan.safeCurrentRpm,
            minimumRpm: fan.safeMinimumRpm,
            maximumRpm: fan.safeMaximumRpm,
            targetRpm: fan.safeTargetRpm,
            mode: fan.normalizedMode,
          ),
    ]);
  }
}
