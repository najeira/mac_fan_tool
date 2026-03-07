import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mac_fan_tool/src/dashboard/dashboard_debug.dart';
import 'package:mac_fan_tool/src/dashboard/dashboard_summary.dart';
import 'package:mac_fan_tool/src/hardware/hardware_controller.dart';
import 'package:mac_fan_tool/src/hardware/hardware_models.dart';

final dashboardIsWideProvider = Provider<bool>((ref) {
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
  final debugOverrides = ref.watch(dashboardDebugOverridesProvider);
  if (debugOverrides.showRefreshing) {
    return true;
  }

  return ref.watch(
    monitorControllerProvider.select((state) => state.isRefreshing),
  );
});

final monitorIsBootstrappingProvider = Provider<bool>((ref) {
  final debugOverrides = ref.watch(dashboardDebugOverridesProvider);
  if (debugOverrides.showBootstrapping) {
    return true;
  }

  return ref.watch(
    monitorControllerProvider.select((state) => state.isBootstrapping),
  );
});

final monitorErrorMessageProvider = Provider<String?>((ref) {
  final debugOverrides = ref.watch(dashboardDebugOverridesProvider);
  if (debugOverrides.showError) {
    return 'Debug override: native bridge reported an injected error state.';
  }

  return ref.watch(
    monitorControllerProvider.select((state) => state.errorMessage),
  );
});

final monitorLastCommandMessageProvider = Provider<String?>((ref) {
  final debugOverrides = ref.watch(dashboardDebugOverridesProvider);
  if (debugOverrides.showSuccess) {
    return 'Debug override: fan command completed successfully.';
  }

  return ref.watch(
    monitorControllerProvider.select((state) => state.lastCommandMessage),
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

final dashboardShowLoadingPanelProvider = Provider<bool>((ref) {
  final isBootstrapping = ref.watch(monitorIsBootstrappingProvider);
  final hasSnapshot = ref.watch(monitorHasInitialSnapshotProvider);
  return isBootstrapping || !hasSnapshot;
});

final dashboardSummaryProvider = Provider<DashboardSummary>((ref) {
  final snapshot = ref.watch(monitorSnapshotProvider);
  return DashboardSummary.fromSnapshot(snapshot);
});

final dashboardHardwareNoteProvider = Provider<String?>((ref) {
  final debugOverrides = ref.watch(dashboardDebugOverridesProvider);
  if (debugOverrides.showHardwareNote) {
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
