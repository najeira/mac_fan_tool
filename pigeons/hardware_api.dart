import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/pigeon/hardware_api.g.dart',
    swiftOut: 'macos/Runner/Pigeon/HardwareApi.g.swift',
    swiftOptions: SwiftOptions(),
  ),
)
enum ThermalStateData { nominal, fair, serious, critical, unknown }

enum SensorKindData { cpu, gpu, memory, ambient, other }

enum FanModeData { automatic, manual }

class SensorReadingData {
  String? id;
  String? name;
  String? unit;
  double? value;
  SensorKindData? kind;
}

class FanReadingData {
  String? id;
  String? name;
  int? currentRpm;
  int? minimumRpm;
  int? maximumRpm;
  int? targetRpm;
  FanModeData? mode;
}

class HardwareCapabilitiesData {
  bool? supportsRawSensors;
  bool? supportsFanControl;
  bool? hasFans;
  String? backend;
  String? note;
}

class HardwareSnapshotData {
  int? capturedAtEpochMs;
  ThermalStateData? thermalState;
  List<SensorReadingData?>? sensors;
  List<FanReadingData?>? fans;
  String? note;
}

@HostApi()
abstract class HardwareHostApi {
  HardwareCapabilitiesData getCapabilities();

  HardwareSnapshotData getSnapshot();

  void setFanMode(String fanId, FanModeData mode);

  void setFanTargetRpm(String fanId, int targetRpm);

  void renewManualFanLease(String fanId);
}
