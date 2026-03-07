import 'package:mac_fan_tool/src/pigeon/hardware_api.g.dart';

export 'package:mac_fan_tool/src/pigeon/hardware_api.g.dart'
    show
        FanModeData,
        FanReadingData,
        HardwareCapabilitiesData,
        HardwareSnapshotData,
        SensorKindData,
        SensorReadingData,
        ThermalStateData;

class DeviceMetadata {
  const DeviceMetadata({
    required this.computerName,
    required this.model,
    required this.architecture,
    required this.osVersion,
    this.note,
  });

  const DeviceMetadata.unknown({this.note})
    : computerName = 'Unknown Mac',
      model = 'Unknown model',
      architecture = 'unknown',
      osVersion = 'unknown';

  final String computerName;
  final String model;
  final String architecture;
  final String osVersion;
  final String? note;
}

HardwareCapabilitiesData unavailableHardwareCapabilities({
  String backend = 'unavailable',
  String? note,
}) {
  return HardwareCapabilitiesData(
    supportsRawSensors: false,
    supportsFanControl: false,
    hasFans: false,
    backend: backend,
    note: note,
  );
}

HardwareSnapshotData emptyHardwareSnapshot({String? note}) {
  return HardwareSnapshotData(
    capturedAtEpochMs: 0,
    thermalState: ThermalStateData.unknown,
    sensors: const <SensorReadingData>[],
    fans: const <FanReadingData>[],
    note: note,
  );
}

extension HardwareCapabilitiesDataX on HardwareCapabilitiesData {
  bool get rawSensorsEnabled => supportsRawSensors ?? false;

  bool get fanControlEnabled => supportsFanControl ?? false;

  bool get fanTelemetryAvailable => hasFans ?? false;

  String get backendLabel => backend ?? 'unavailable';
}

extension HardwareSnapshotDataX on HardwareSnapshotData {
  DateTime get capturedAt =>
      DateTime.fromMillisecondsSinceEpoch(capturedAtEpochMs ?? 0);

  ThermalStateData get thermalLevel => thermalState ?? ThermalStateData.unknown;

  List<SensorReadingData> get sensorReadings {
    return [...?sensors?.whereType<SensorReadingData>()];
  }

  List<FanReadingData> get fanReadings {
    return [...?fans?.whereType<FanReadingData>()];
  }
}

extension SensorReadingDataX on SensorReadingData {
  String get stableId => id ?? 'sensor-${name ?? 'unknown'}';

  String get displayName => name ?? 'Unnamed sensor';

  String get displayUnit => unit ?? '';

  double get numericValue => value ?? 0;

  SensorKindData get normalizedKind => kind ?? SensorKindData.other;
}

extension FanReadingDataX on FanReadingData {
  String get stableId => id ?? 'fan-${name ?? 'unknown'}';

  String get displayName => name ?? 'Unnamed fan';

  int get safeCurrentRpm => currentRpm ?? 0;

  int get safeMinimumRpm => minimumRpm ?? 0;

  int get safeMaximumRpm => maximumRpm ?? 0;

  int? get safeTargetRpm => targetRpm;

  FanModeData get normalizedMode => mode ?? FanModeData.automatic;
}

class MonitorState {
  MonitorState({
    required this.device,
    required this.capabilities,
    required this.snapshot,
    required this.history,
    required this.isBootstrapping,
    required this.isRefreshing,
    this.activeFanCommandId,
    this.commandErrorMessage,
    this.errorMessage,
    this.lastCommandMessage,
  });

  factory MonitorState.initial() {
    return MonitorState(
      device: const DeviceMetadata.unknown(),
      capabilities: unavailableHardwareCapabilities(),
      snapshot: emptyHardwareSnapshot(
        note: 'Waiting for the native hardware bridge to initialize.',
      ),
      history: <HardwareSnapshotData>[],
      isBootstrapping: true,
      isRefreshing: false,
    );
  }

  static const Object _sentinel = Object();

  final DeviceMetadata device;
  final HardwareCapabilitiesData capabilities;
  final HardwareSnapshotData snapshot;
  final List<HardwareSnapshotData> history;
  final bool isBootstrapping;
  final bool isRefreshing;
  final String? activeFanCommandId;
  final String? commandErrorMessage;
  final String? errorMessage;
  final String? lastCommandMessage;

  MonitorState copyWith({
    DeviceMetadata? device,
    HardwareCapabilitiesData? capabilities,
    HardwareSnapshotData? snapshot,
    List<HardwareSnapshotData>? history,
    bool? isBootstrapping,
    bool? isRefreshing,
    Object? activeFanCommandId = _sentinel,
    Object? commandErrorMessage = _sentinel,
    Object? errorMessage = _sentinel,
    Object? lastCommandMessage = _sentinel,
  }) {
    return MonitorState(
      device: device ?? this.device,
      capabilities: capabilities ?? this.capabilities,
      snapshot: snapshot ?? this.snapshot,
      history: history ?? this.history,
      isBootstrapping: isBootstrapping ?? this.isBootstrapping,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      activeFanCommandId: identical(activeFanCommandId, _sentinel)
          ? this.activeFanCommandId
          : activeFanCommandId as String?,
      commandErrorMessage: identical(commandErrorMessage, _sentinel)
          ? this.commandErrorMessage
          : commandErrorMessage as String?,
      errorMessage: identical(errorMessage, _sentinel)
          ? this.errorMessage
          : errorMessage as String?,
      lastCommandMessage: identical(lastCommandMessage, _sentinel)
          ? this.lastCommandMessage
          : lastCommandMessage as String?,
    );
  }
}
