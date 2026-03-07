import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  return ref.watch(
    monitorControllerProvider.select((state) => state.isRefreshing),
  );
});

final monitorIsBootstrappingProvider = Provider<bool>((ref) {
  return ref.watch(
    monitorControllerProvider.select((state) => state.isBootstrapping),
  );
});

final monitorErrorMessageProvider = Provider<String?>((ref) {
  return ref.watch(
    monitorControllerProvider.select((state) => state.errorMessage),
  );
});

final monitorLastCommandMessageProvider = Provider<String?>((ref) {
  return ref.watch(
    monitorControllerProvider.select((state) => state.lastCommandMessage),
  );
});

final monitorActiveFanCommandIdProvider = Provider<String?>((ref) {
  return ref.watch(
    monitorControllerProvider.select((state) => state.activeFanCommandId),
  );
});

final dashboardSummaryProvider = Provider<DashboardSummary>((ref) {
  final snapshot = ref.watch(monitorSnapshotProvider);
  return DashboardSummary.fromSnapshot(snapshot);
});

final dashboardHardwareNoteProvider = Provider<String?>((ref) {
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
