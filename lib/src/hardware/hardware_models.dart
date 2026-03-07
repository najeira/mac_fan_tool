enum SensorKind { cpu, gpu, memory, ambient, other }

enum FanControlMode { automatic, manual }

enum ThermalStateLevel { nominal, fair, serious, critical, unknown }

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

class HardwareCapabilities {
  const HardwareCapabilities({
    required this.supportsRawSensors,
    required this.supportsFanControl,
    required this.hasFans,
    required this.backend,
    this.note,
  });

  const HardwareCapabilities.unavailable({
    this.backend = 'unavailable',
    this.note,
  }) : supportsRawSensors = false,
       supportsFanControl = false,
       hasFans = false;

  final bool supportsRawSensors;
  final bool supportsFanControl;
  final bool hasFans;
  final String backend;
  final String? note;
}

class SensorReading {
  const SensorReading({
    required this.id,
    required this.name,
    required this.unit,
    required this.value,
    required this.kind,
  });

  final String id;
  final String name;
  final String unit;
  final double value;
  final SensorKind kind;
}

class FanReading {
  const FanReading({
    required this.id,
    required this.name,
    required this.currentRpm,
    required this.minimumRpm,
    required this.maximumRpm,
    required this.mode,
    this.targetRpm,
  });

  final String id;
  final String name;
  final int currentRpm;
  final int minimumRpm;
  final int maximumRpm;
  final int? targetRpm;
  final FanControlMode mode;
}

class HardwareSnapshot {
  const HardwareSnapshot({
    required this.capturedAt,
    required this.thermalState,
    required this.sensors,
    required this.fans,
    this.note,
  });

  HardwareSnapshot.empty({this.note})
    : capturedAt = DateTime.fromMillisecondsSinceEpoch(0),
      thermalState = ThermalStateLevel.unknown,
      sensors = const <SensorReading>[],
      fans = const <FanReading>[];

  final DateTime capturedAt;
  final ThermalStateLevel thermalState;
  final List<SensorReading> sensors;
  final List<FanReading> fans;
  final String? note;
}

class MonitorState {
  const MonitorState({
    required this.device,
    required this.capabilities,
    required this.snapshot,
    required this.history,
    required this.isBootstrapping,
    required this.isRefreshing,
    this.activeFanCommandId,
    this.errorMessage,
    this.lastCommandMessage,
  });

  factory MonitorState.initial() {
    return MonitorState(
      device: const DeviceMetadata.unknown(),
      capabilities: const HardwareCapabilities.unavailable(),
      snapshot: HardwareSnapshot.empty(
        note: 'Waiting for the native hardware bridge to initialize.',
      ),
      history: <HardwareSnapshot>[],
      isBootstrapping: true,
      isRefreshing: false,
    );
  }

  static const Object _sentinel = Object();

  final DeviceMetadata device;
  final HardwareCapabilities capabilities;
  final HardwareSnapshot snapshot;
  final List<HardwareSnapshot> history;
  final bool isBootstrapping;
  final bool isRefreshing;
  final String? activeFanCommandId;
  final String? errorMessage;
  final String? lastCommandMessage;

  MonitorState copyWith({
    DeviceMetadata? device,
    HardwareCapabilities? capabilities,
    HardwareSnapshot? snapshot,
    List<HardwareSnapshot>? history,
    bool? isBootstrapping,
    bool? isRefreshing,
    Object? activeFanCommandId = _sentinel,
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
      errorMessage: identical(errorMessage, _sentinel)
          ? this.errorMessage
          : errorMessage as String?,
      lastCommandMessage: identical(lastCommandMessage, _sentinel)
          ? this.lastCommandMessage
          : lastCommandMessage as String?,
    );
  }
}
