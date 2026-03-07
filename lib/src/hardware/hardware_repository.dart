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
    try {
      final info = await _deviceInfoPlugin.macOsInfo;

      return DeviceMetadata(
        computerName: info.computerName,
        model: info.model,
        architecture: info.arch,
        osVersion: info.osRelease,
      );
    } on MissingPluginException {
      return const DeviceMetadata.unknown(
        note:
            'device_info_plus is not available in tests until plugin registration runs.',
      );
    } on PlatformException catch (error) {
      return DeviceMetadata.unknown(
        note: 'Device metadata is unavailable: ${error.message ?? error.code}',
      );
    } catch (error) {
      return DeviceMetadata.unknown(
        note: 'Device metadata is unavailable: $error',
      );
    }
  }

  Future<HardwareCapabilitiesData> loadCapabilities() async {
    try {
      final data = await _api.getCapabilities();
      return HardwareCapabilitiesData(
        supportsRawSensors: data.supportsRawSensors ?? false,
        supportsFanControl: data.supportsFanControl ?? false,
        hasFans: data.hasFans ?? false,
        backend: data.backend ?? 'native-bridge',
        note: data.note,
      );
    } on MissingPluginException {
      return unavailableHardwareCapabilities(
        backend: 'pigeon-missing',
        note:
            'The native hardware bridge is not registered in this environment yet.',
      );
    } on PlatformException catch (error) {
      return unavailableHardwareCapabilities(
        backend: 'pigeon-error',
        note: 'Native capability probe failed: ${error.message ?? error.code}',
      );
    } catch (error) {
      return unavailableHardwareCapabilities(
        backend: 'pigeon-error',
        note: 'Native capability probe failed: $error',
      );
    }
  }

  Future<HardwareSnapshotData> loadSnapshot() async {
    try {
      final data = await _api.getSnapshot();
      return HardwareSnapshotData(
        capturedAtEpochMs:
            data.capturedAtEpochMs ?? DateTime.now().millisecondsSinceEpoch,
        thermalState: data.thermalState ?? ThermalStateData.unknown,
        sensors: [
          for (final sensor in data.sensors ?? const <SensorReadingData?>[])
            if (sensor != null)
              SensorReadingData(
                id: sensor.id ?? 'sensor-${sensor.name ?? 'unknown'}',
                name: sensor.name ?? 'Unnamed sensor',
                unit: sensor.unit ?? '',
                value: sensor.value ?? 0,
                kind: sensor.kind ?? SensorKindData.other,
              ),
        ],
        fans: [
          for (final fan in data.fans ?? const <FanReadingData?>[])
            if (fan != null)
              FanReadingData(
                id: fan.id ?? 'fan-${fan.name ?? 'unknown'}',
                name: fan.name ?? 'Unnamed fan',
                currentRpm: fan.currentRpm ?? 0,
                minimumRpm: fan.minimumRpm ?? 0,
                maximumRpm: fan.maximumRpm ?? 0,
                targetRpm: fan.targetRpm,
                mode: fan.mode ?? FanModeData.automatic,
              ),
        ],
        note: data.note,
      );
    } on MissingPluginException {
      return emptyHardwareSnapshot(
        note:
            'The native hardware bridge is not registered in this environment yet.',
      );
    } on PlatformException catch (error) {
      return emptyHardwareSnapshot(
        note: 'Telemetry refresh failed: ${error.message ?? error.code}',
      );
    } catch (error) {
      return emptyHardwareSnapshot(note: 'Telemetry refresh failed: $error');
    }
  }

  Future<void> setFanMode(String fanId, FanModeData mode) async {
    try {
      await _api.setFanMode(fanId, mode);
    } on PlatformException catch (error) {
      throw StateError(error.message ?? error.code);
    } catch (error) {
      throw StateError(error.toString());
    }
  }

  Future<void> setFanTargetRpm(String fanId, int targetRpm) async {
    try {
      await _api.setFanTargetRpm(fanId, targetRpm);
    } on PlatformException catch (error) {
      throw StateError(error.message ?? error.code);
    } catch (error) {
      throw StateError(error.toString());
    }
  }
}
