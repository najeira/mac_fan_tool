import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mac_fan_tool/src/hardware/hardware_models.dart';
import 'package:mac_fan_tool/src/hardware/hardware_repository.dart';

final hardwareRepositoryProvider = Provider<HardwareRepository>((ref) {
  return HardwareRepository();
});

final monitorControllerProvider =
    NotifierProvider<MonitorController, MonitorState>(MonitorController.new);

final transientNoticeDurationProvider = Provider<Duration>((ref) {
  return const Duration(seconds: 4);
});

class MonitorController extends Notifier<MonitorState> {
  Timer? _pollTimer;
  Timer? _transientNoticeTimer;
  bool _refreshInFlight = false;

  HardwareRepository get _repository => ref.read(hardwareRepositoryProvider);
  Duration get _transientNoticeDuration =>
      ref.read(transientNoticeDurationProvider);

  @override
  MonitorState build() {
    ref.onDispose(() {
      _pollTimer?.cancel();
      _transientNoticeTimer?.cancel();
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
        capabilities: results[1] as HardwareCapabilitiesData,
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

  Future<void> setFanAutomatic(FanReadingData fan) async {
    final fanId = fan.id;
    if (fanId == null || fanId.isEmpty) {
      _showTransientNotice(
        const MonitorNotice(
          tone: MonitorNoticeTone.error,
          message: 'Fan command failed: missing fan id.',
        ),
      );
      return;
    }

    await _runFanCommand(
      fanId,
      () => _repository.setFanMode(fanId, FanModeData.automatic),
      successMessage: '${fan.displayName} is back in automatic mode.',
    );
  }

  Future<void> setFanTargetRpm(FanReadingData fan, int targetRpm) async {
    final fanId = fan.id;
    if (fanId == null || fanId.isEmpty) {
      _showTransientNotice(
        const MonitorNotice(
          tone: MonitorNoticeTone.error,
          message: 'Fan command failed: missing fan id.',
        ),
      );
      return;
    }

    final clampedTarget = targetRpm
        .clamp(fan.safeMinimumRpm, fan.safeMaximumRpm)
        .toInt();

    await _runFanCommand(
      fanId,
      () async {
        await _repository.setFanMode(fanId, FanModeData.manual);
        await _repository.setFanTargetRpm(fanId, clampedTarget);
      },
      successMessage: '${fan.displayName} target set to $clampedTarget RPM.',
    );
  }

  Future<void> _runFanCommand(
    String fanId,
    Future<void> Function() action, {
    required String successMessage,
  }) async {
    _clearTransientNotice();
    state = state.copyWith(activeFanCommandId: fanId, errorMessage: null);

    try {
      await action();
      state = state.copyWith(activeFanCommandId: null);
      _showTransientNotice(
        MonitorNotice(tone: MonitorNoticeTone.success, message: successMessage),
      );
      await refresh(showSpinner: false);
    } catch (error) {
      state = state.copyWith(activeFanCommandId: null);
      _showTransientNotice(
        MonitorNotice(
          tone: MonitorNoticeTone.error,
          message: 'Fan command failed: $error',
        ),
      );
    }
  }

  void dismissTransientNotice() {
    _clearTransientNotice();
  }

  void _showTransientNotice(MonitorNotice notice) {
    _transientNoticeTimer?.cancel();
    state = state.copyWith(transientNotice: notice);
    _transientNoticeTimer = Timer(
      _transientNoticeDuration,
      _clearTransientNotice,
    );
  }

  void _clearTransientNotice() {
    _transientNoticeTimer?.cancel();
    _transientNoticeTimer = null;
    state = state.copyWith(transientNotice: null);
  }

  List<HardwareSnapshotData> _appendHistory(HardwareSnapshotData snapshot) {
    final nextHistory = <HardwareSnapshotData>[...state.history, snapshot];

    if (nextHistory.length <= 90) {
      return nextHistory;
    }

    return nextHistory.sublist(nextHistory.length - 90);
  }
}
