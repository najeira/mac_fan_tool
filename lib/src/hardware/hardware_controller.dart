import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mac_fan_tool/src/hardware/hardware_models.dart';
import 'package:mac_fan_tool/src/hardware/hardware_repository.dart';

final hardwareRepositoryProvider = Provider<HardwareRepository>((ref) {
  return HardwareRepository();
});

final monitorControllerProvider =
    NotifierProvider<MonitorController, MonitorState>(MonitorController.new);

class MonitorController extends Notifier<MonitorState> {
  Timer? _pollTimer;
  bool _refreshInFlight = false;
  late final HardwareRepository _repository;

  @override
  MonitorState build() {
    _repository = ref.read(hardwareRepositoryProvider);
    ref.onDispose(() {
      _pollTimer?.cancel();
    });
    unawaited(_bootstrap());
    return MonitorState.initial();
  }

  Future<void> _bootstrap() async {
    try {
      final results = await Future.wait<Object>([
        _repository.loadDeviceMetadata(),
        _repository.loadCapabilities(),
      ]);

      state = state.copyWith(
        device: results[0] as DeviceMetadata,
        capabilities: results[1] as HardwareCapabilities,
        isBootstrapping: false,
      );

      await refresh(showSpinner: false);

      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        unawaited(refresh(showSpinner: false));
      });
    } catch (error) {
      state = state.copyWith(
        isBootstrapping: false,
        errorMessage: 'Initialization failed: $error',
      );
    }
  }

  Future<void> refresh({bool showSpinner = true}) async {
    if (_refreshInFlight) {
      return;
    }

    _refreshInFlight = true;
    state = state.copyWith(isRefreshing: showSpinner, errorMessage: null);

    try {
      final snapshot = await _repository.loadSnapshot();
      state = state.copyWith(
        snapshot: snapshot,
        history: _appendHistory(snapshot),
        isRefreshing: false,
      );
    } catch (error) {
      state = state.copyWith(
        isRefreshing: false,
        errorMessage: 'Telemetry refresh failed: $error',
      );
    } finally {
      _refreshInFlight = false;
    }
  }

  Future<void> setFanAutomatic(FanReading fan) async {
    await _runFanCommand(
      fan.id,
      () => _repository.setFanMode(fan.id, FanControlMode.automatic),
      successMessage: '${fan.name} is back in automatic mode.',
    );
  }

  Future<void> setFanTargetRpm(FanReading fan, int targetRpm) async {
    final clampedTarget = targetRpm
        .clamp(fan.minimumRpm, fan.maximumRpm)
        .toInt();

    await _runFanCommand(fan.id, () async {
      await _repository.setFanMode(fan.id, FanControlMode.manual);
      await _repository.setFanTargetRpm(fan.id, clampedTarget);
    }, successMessage: '${fan.name} target set to $clampedTarget RPM.');
  }

  Future<void> _runFanCommand(
    String fanId,
    Future<void> Function() action, {
    required String successMessage,
  }) async {
    state = state.copyWith(
      activeFanCommandId: fanId,
      errorMessage: null,
      lastCommandMessage: null,
    );

    try {
      await action();
      state = state.copyWith(
        activeFanCommandId: null,
        lastCommandMessage: successMessage,
      );
      await refresh(showSpinner: false);
    } catch (error) {
      state = state.copyWith(
        activeFanCommandId: null,
        errorMessage: 'Fan command failed: $error',
      );
    }
  }

  List<HardwareSnapshot> _appendHistory(HardwareSnapshot snapshot) {
    final nextHistory = <HardwareSnapshot>[...state.history, snapshot];

    if (nextHistory.length <= 90) {
      return nextHistory;
    }

    return nextHistory.sublist(nextHistory.length - 90);
  }
}
