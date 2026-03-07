import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mac_fan_tool/src/dashboard/dashboard_debug.dart';
import 'package:mac_fan_tool/src/dashboard/dashboard_summary.dart';
import 'package:mac_fan_tool/src/dashboard/thermal_trend.dart';
import 'package:mac_fan_tool/src/dashboard/widgets/dashboard_common.dart';
import 'package:mac_fan_tool/src/hardware/hardware_controller.dart';
import 'package:mac_fan_tool/src/hardware/hardware_models.dart';

final isWideProvider = Provider<bool>((ref) {
  return false;
}, dependencies: const []);

final monitorSnapshotProvider = Provider<HardwareSnapshotData>((ref) {
  return ref.watch(monitorControllerProvider.select((state) => state.snapshot));
});

final monitorHistoryProvider = Provider<List<HardwareSnapshotData>>((ref) {
  return ref.watch(monitorControllerProvider.select((state) => state.history));
});

final monitorDeviceProvider = Provider<DeviceMetadata>((ref) {
  return ref.watch(monitorControllerProvider.select((state) => state.device));
});

final monitorCapabilitiesProvider = Provider<HardwareCapabilitiesData>((ref) {
  return ref.watch(
    monitorControllerProvider.select((state) => state.capabilities),
  );
});

final monitorIsRefreshingProvider = Provider<bool>((ref) {
  final debugFlags = ref.watch(debugFlagsProvider);
  if (debugFlags.showRefreshing) {
    return true;
  }

  return ref.watch(
    monitorControllerProvider.select((state) => state.isRefreshing),
  );
});

final monitorIsBootstrappingProvider = Provider<bool>((ref) {
  final debugFlags = ref.watch(debugFlagsProvider);
  if (debugFlags.showBootstrapping) {
    return true;
  }

  return ref.watch(
    monitorControllerProvider.select((state) => state.isBootstrapping),
  );
});

final monitorErrorMessageProvider = Provider<String?>((ref) {
  final debugFlags = ref.watch(debugFlagsProvider);
  if (debugFlags.showError) {
    return 'Debug override: native bridge reported an injected error state.';
  }

  return ref.watch(
    monitorControllerProvider.select((state) => state.errorMessage),
  );
});

final monitorTransientNoticeProvider = Provider<MonitorNotice?>((ref) {
  final debugFlags = ref.watch(debugFlagsProvider);
  if (debugFlags.showSuccess) {
    return const MonitorNotice(
      tone: MonitorNoticeTone.success,
      message: 'Debug override: fan command completed successfully.',
    );
  }

  return ref.watch(
    monitorControllerProvider.select((state) => state.transientNotice),
  );
});

final monitorActiveFanCommandIdProvider = Provider<String?>((ref) {
  return ref.watch(
    monitorControllerProvider.select((state) => state.activeFanCommandId),
  );
});

final monitorHasInitialSnapshotProvider = Provider<bool>((ref) {
  final snapshot = ref.watch(monitorSnapshotProvider);
  return (snapshot.capturedAtEpochMs ?? 0) > 0;
});

final showLoadingPanelProvider = Provider<bool>((ref) {
  final isBootstrapping = ref.watch(monitorIsBootstrappingProvider);
  final hasSnapshot = ref.watch(monitorHasInitialSnapshotProvider);
  return isBootstrapping || !hasSnapshot;
});

final summaryProvider = Provider<DashboardSummary>((ref) {
  final snapshot = ref.watch(monitorSnapshotProvider);
  return DashboardSummary.fromSnapshot(snapshot);
});

final fanSummaryProvider = Provider<FanSummary?>((ref) {
  final snapshot = ref.watch(monitorSnapshotProvider);
  if (snapshot.fanReadings.isEmpty) {
    return null;
  }

  return FanSummary.fromFans(snapshot.fanReadings);
});

final fanReadingProvider = Provider.family<FanReadingData?, String>((
  ref,
  fanId,
) {
  return ref.watch(
    monitorSnapshotProvider.select((snapshot) {
      for (final fan in snapshot.fanReadings) {
        if (fan.stableId == fanId) {
          return fan;
        }
      }
      return null;
    }),
  );
});

final thermalTrendProvider = Provider<ThermalTrendModel>((ref) {
  final history = ref.watch(monitorHistoryProvider);
  return ThermalTrendModel.fromHistory(history);
});

final hardwareNoteProvider = Provider<String?>((ref) {
  final debugFlags = ref.watch(debugFlagsProvider);
  if (debugFlags.showHardwareNote) {
    return 'Debug override: showing a simulated hardware note for layout testing.';
  }

  final notes = ref.watch(
    monitorControllerProvider.select(
      (state) => (
        snapshotNote: state.snapshot.note,
        capabilitiesNote: state.capabilities.note,
        deviceNote: state.device.note,
      ),
    ),
  );

  return notes.snapshotNote ?? notes.capabilitiesNote ?? notes.deviceNote;
});

final persistentStatusBannersProvider = Provider<List<(NoticeTone, String)>>((
  ref,
) {
  final errorMessage = ref.watch(monitorErrorMessageProvider);
  final hardwareNote = ref.watch(hardwareNoteProvider);

  return [
    if (errorMessage != null) (NoticeTone.error, errorMessage),
    if (hardwareNote != null) (NoticeTone.info, hardwareNote),
  ];
});
