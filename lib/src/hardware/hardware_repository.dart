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

  Future<HardwareCapabilities> loadCapabilities() async {
    try {
      final data = await _api.getCapabilities();
      return HardwareCapabilities(
        supportsRawSensors: data.supportsRawSensors ?? false,
        supportsFanControl: data.supportsFanControl ?? false,
        hasFans: data.hasFans ?? false,
        backend: data.backend ?? 'native-bridge',
        note: data.note,
      );
    } on MissingPluginException {
      return const HardwareCapabilities.unavailable(
        backend: 'pigeon-missing',
        note:
            'The native hardware bridge is not registered in this environment yet.',
      );
    } on PlatformException catch (error) {
      return HardwareCapabilities.unavailable(
        backend: 'pigeon-error',
        note: 'Native capability probe failed: ${error.message ?? error.code}',
      );
    } catch (error) {
      return HardwareCapabilities.unavailable(
        backend: 'pigeon-error',
        note: 'Native capability probe failed: $error',
      );
    }
  }

  Future<HardwareSnapshot> loadSnapshot() async {
    try {
      final data = await _api.getSnapshot();
      return HardwareSnapshot(
        capturedAt: DateTime.fromMillisecondsSinceEpoch(
          data.capturedAtEpochMs ?? DateTime.now().millisecondsSinceEpoch,
        ),
        thermalState: _mapThermalState(data.thermalState),
        sensors: [
          for (final sensor in data.sensors ?? const <SensorReadingData?>[])
            if (sensor != null)
              SensorReading(
                id: sensor.id ?? 'sensor-${sensor.name ?? 'unknown'}',
                name: sensor.name ?? 'Unnamed sensor',
                unit: sensor.unit ?? '',
                value: sensor.value ?? 0,
                kind: _mapSensorKind(sensor.kind),
              ),
        ],
        fans: [
          for (final fan in data.fans ?? const <FanReadingData?>[])
            if (fan != null)
              FanReading(
                id: fan.id ?? 'fan-${fan.name ?? 'unknown'}',
                name: fan.name ?? 'Unnamed fan',
                currentRpm: fan.currentRpm ?? 0,
                minimumRpm: fan.minimumRpm ?? 0,
                maximumRpm: fan.maximumRpm ?? 0,
                targetRpm: fan.targetRpm,
                mode: _mapFanMode(fan.mode),
              ),
        ],
        note: data.note,
      );
    } on MissingPluginException {
      return HardwareSnapshot.empty(
        note:
            'The native hardware bridge is not registered in this environment yet.',
      );
    } on PlatformException catch (error) {
      return HardwareSnapshot.empty(
        note: 'Telemetry refresh failed: ${error.message ?? error.code}',
      );
    } catch (error) {
      return HardwareSnapshot.empty(note: 'Telemetry refresh failed: $error');
    }
  }

  Future<void> setFanMode(String fanId, FanControlMode mode) async {
    try {
      await _api.setFanMode(fanId, _toPigeonMode(mode));
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

  FanModeData _toPigeonMode(FanControlMode mode) {
    switch (mode) {
      case FanControlMode.automatic:
        return FanModeData.automatic;
      case FanControlMode.manual:
        return FanModeData.manual;
    }
  }

  FanControlMode _mapFanMode(FanModeData? mode) {
    switch (mode) {
      case FanModeData.manual:
        return FanControlMode.manual;
      case FanModeData.automatic:
      case null:
        return FanControlMode.automatic;
    }
  }

  SensorKind _mapSensorKind(SensorKindData? kind) {
    switch (kind) {
      case SensorKindData.cpu:
        return SensorKind.cpu;
      case SensorKindData.gpu:
        return SensorKind.gpu;
      case SensorKindData.memory:
        return SensorKind.memory;
      case SensorKindData.ambient:
        return SensorKind.ambient;
      case SensorKindData.other:
      case null:
        return SensorKind.other;
    }
  }

  ThermalStateLevel _mapThermalState(ThermalStateData? state) {
    switch (state) {
      case ThermalStateData.nominal:
        return ThermalStateLevel.nominal;
      case ThermalStateData.fair:
        return ThermalStateLevel.fair;
      case ThermalStateData.serious:
        return ThermalStateLevel.serious;
      case ThermalStateData.critical:
        return ThermalStateLevel.critical;
      case ThermalStateData.unknown:
      case null:
        return ThermalStateLevel.unknown;
    }
  }
}
