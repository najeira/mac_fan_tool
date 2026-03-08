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

final manualLeaseHeartbeatIntervalProvider = Provider<Duration>((ref) {
  return const Duration(seconds: 30);
});

class MonitorController extends Notifier<MonitorState> {
  Timer? _pollTimer;
  Timer? _transientNoticeTimer;
  Timer? _manualLeaseHeartbeatTimer;

  bool _refreshInFlight = false;
  bool _manualLeaseRenewalInFlight = false;

  bool _isDisposed = false;

  final Set<String> _manualLeaseFanIds = <String>{};

  HardwareRepository get _repository => ref.read(hardwareRepositoryProvider);

  Duration get _transientNoticeDuration =>
      ref.read(transientNoticeDurationProvider);

  Duration get _manualLeaseHeartbeatInterval =>
      ref.read(manualLeaseHeartbeatIntervalProvider);

  @override
  MonitorState build() {
    _isDisposed = false;

    ref.onDispose(() {
      _isDisposed = true;
      _pollTimer?.cancel();
      _pollTimer = null;
      _transientNoticeTimer?.cancel();
      _transientNoticeTimer = null;
      _manualLeaseHeartbeatTimer?.cancel();
      _manualLeaseHeartbeatTimer = null;
      _manualLeaseFanIds.clear();
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
      if (_isDisposed) {
        return;
      }

      state = state.copyWith(
        device: results[0] as DeviceMetadata,
        capabilities: results[1] as HardwareCapabilitiesData,
        isBootstrapping: false,
      );

      await refresh();
      if (_isDisposed) {
        return;
      }

      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        unawaited(refresh());
      });
    } catch (error) {
      if (_isDisposed) {
        return;
      }

      state = state.copyWith(
        isBootstrapping: false,
        errorMessage: 'Initialization failed: $error',
      );
    }
  }

  Future<bool> refresh() async {
    if (_isDisposed) {
      return false;
    }

    if (_refreshInFlight) {
      return true;
    }
    _refreshInFlight = true;

    try {
      final snapshot = await _repository.loadSnapshot();
      if (_isDisposed) {
        return false;
      }

      state = state.copyWith(
        snapshot: snapshot,
        history: _appendHistory(snapshot),
        errorMessage: null,
      );
      _pruneManualLeaseFanIds(snapshot);
      return true;
    } catch (error) {
      if (_isDisposed) {
        return false;
      }

      state = state.copyWith(errorMessage: 'Telemetry refresh failed: $error');
      return false;
    } finally {
      _refreshInFlight = false;
    }
  }

  Future<void> setFanAutomatic(FanReadingData fan) async {
    final fanId = fan.id;
    if (fanId == null || fanId.isEmpty) {
      return;
    }

    await _runFanCommand(
      fanId,
      () => _repository.setFanMode(fanId, FanModeData.automatic),
      successMessage: '${fan.displayName} is back in automatic mode.',
      onActionApplied: () => _deactivateManualLease(fanId),
    );
  }

  Future<void> setFanTargetRpm(FanReadingData fan, int targetRpm) async {
    final fanId = fan.id;
    if (fanId == null || fanId.isEmpty) {
      return;
    }

    await _runFanCommand(
      fanId,
      () => _repository.setFanTargetRpm(fanId, targetRpm),
      successMessage: '${fan.displayName} target set to $targetRpm RPM.',
      onActionApplied: () => _activateManualLease(fanId),
    );
  }

  Future<void> _runFanCommand(
    String fanId,
    Future<void> Function() action, {
    required String successMessage,
    void Function()? onActionApplied,
  }) async {
    _clearTransientNotice();
    if (_isDisposed) {
      return;
    }

    state = state.copyWith(
      activeFanCommandIds: {...state.activeFanCommandIds, fanId},
    );

    try {
      await action();
      if (_isDisposed) {
        return;
      }

      onActionApplied?.call();

      final refreshSucceeded = await refresh();
      if (_isDisposed) {
        return;
      }

      state = state.copyWith(
        activeFanCommandIds: _removeActiveFanCommandId(fanId),
      );

      _showTransientNotice(
        MonitorNotice(
          tone: refreshSucceeded
              ? MonitorNoticeTone.success
              : MonitorNoticeTone.info,
          message: refreshSucceeded
              ? successMessage
              : '$successMessage Telemetry refresh failed, so the dashboard may be stale.',
        ),
      );
    } catch (error) {
      if (_isDisposed) {
        return;
      }

      state = state.copyWith(
        activeFanCommandIds: _removeActiveFanCommandId(fanId),
      );

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
    if (_isDisposed) {
      return;
    }

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
    if (_isDisposed) {
      return;
    }
    state = state.copyWith(transientNotice: null);
  }

  List<HardwareSnapshotData> _appendHistory(HardwareSnapshotData snapshot) {
    final nextHistory = <HardwareSnapshotData>[...state.history, snapshot];
    final overflow = nextHistory.length - 90;
    if (overflow <= 0) {
      return nextHistory;
    }
    return nextHistory.sublist(overflow);
  }

  Set<String> _removeActiveFanCommandId(String fanId) {
    final activeFanCommandIds = {...state.activeFanCommandIds};
    activeFanCommandIds.remove(fanId);
    return activeFanCommandIds;
  }

  void _activateManualLease(String fanId) {
    _manualLeaseFanIds.add(fanId);
    _syncManualLeaseHeartbeat();
  }

  void _deactivateManualLease(String fanId) {
    _manualLeaseFanIds.remove(fanId);
    _syncManualLeaseHeartbeat();
  }

  void _pruneManualLeaseFanIds(HardwareSnapshotData snapshot) {
    final manualFanIds = snapshot.fanReadings
        .where((fan) => fan.normalizedMode == FanModeData.manual)
        .map((fan) => fan.id)
        .whereType<String>()
        .toSet();

    _manualLeaseFanIds.removeWhere((fanId) => !manualFanIds.contains(fanId));
    _syncManualLeaseHeartbeat();
  }

  void _syncManualLeaseHeartbeat() {
    if (_isDisposed) {
      return;
    }

    _manualLeaseHeartbeatTimer?.cancel();
    _manualLeaseHeartbeatTimer = null;

    if (_manualLeaseFanIds.isEmpty) {
      return;
    }

    _manualLeaseHeartbeatTimer = Timer.periodic(
      _manualLeaseHeartbeatInterval,
      (_) => unawaited(_renewManualLeases()),
    );
  }

  Future<void> _renewManualLeases() async {
    if (_isDisposed ||
        _manualLeaseRenewalInFlight ||
        _manualLeaseFanIds.isEmpty) {
      return;
    }

    _manualLeaseRenewalInFlight = true;
    try {
      final fanIds = List<String>.of(_manualLeaseFanIds);
      for (final fanId in fanIds) {
        if (_isDisposed) {
          return;
        }

        try {
          await _repository.renewManualFanLease(fanId);
        } catch (_) {
          _manualLeaseFanIds.remove(fanId);
        }
      }
    } finally {
      _manualLeaseRenewalInFlight = false;
      _syncManualLeaseHeartbeat();
    }
  }
}
