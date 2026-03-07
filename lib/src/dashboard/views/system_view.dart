import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mac_fan_tool/src/dashboard/dashboard_ref.dart';
import 'package:mac_fan_tool/src/dashboard/dashboard_state.dart';
import 'package:mac_fan_tool/src/dashboard/dashboard_support.dart';
import 'package:mac_fan_tool/src/dashboard/widgets/dashboard_common.dart';
import 'package:mac_fan_tool/src/dashboard/widgets/fan_control_card.dart';
import 'package:mac_fan_tool/src/hardware/hardware_models.dart';

class SystemView extends ConsumerWidget {
  const SystemView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = ref.watch(isWideProvider);
    const infoPanel = _SystemInfoPanel();
    const fansPanel = _FansPanel();

    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: infoPanel),
          const SizedBox(width: 20),
          Expanded(child: fansPanel),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [infoPanel, SizedBox(height: 20), fansPanel],
    );
  }
}

class _SystemInfoPanel extends ConsumerWidget {
  const _SystemInfoPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(monitorDeviceProvider);
    final capabilities = ref.watch(monitorCapabilitiesProvider);
    final snapshot = ref.watch(monitorSnapshotProvider);
    final summary = ref.watch(summaryProvider);

    return SectionPanel(
      title: 'Hardware Bridge',
      subtitle:
          'Device identity, backend status, and the amount of data currently visible to the dashboard.',
      child: Column(
        children: [
          KeyValueRow(label: 'Computer', value: device.computerName),
          const Divider(height: 24),
          KeyValueRow(label: 'Model', value: device.model),
          const Divider(height: 24),
          KeyValueRow(label: 'Architecture', value: device.architecture),
          const Divider(height: 24),
          KeyValueRow(label: 'macOS Release', value: device.osVersion),
          const Divider(height: 24),
          KeyValueRow(label: 'Backend', value: capabilities.backendLabel),
          const Divider(height: 24),
          KeyValueRow(
            label: 'Raw Sensors',
            value: capabilities.rawSensorsEnabled
                ? '${summary.sensorCount} channels'
                : 'Not available yet',
          ),
          const Divider(height: 24),
          KeyValueRow(
            label: 'Fans',
            value: capabilities.fanTelemetryAvailable
                ? '${snapshot.fanReadings.length} reported'
                : 'Unavailable',
          ),
          const Divider(height: 24),
          KeyValueRow(
            label: 'Fan Control',
            value: capabilities.fanControlEnabled ? 'Writable' : 'Read only',
          ),
          const Divider(height: 24),
          KeyValueRow(
            label: 'Composite Thermal',
            value: formatTemperature(summary.overallTemperature),
          ),
        ],
      ),
    );
  }
}

class _FansPanel extends ConsumerWidget {
  const _FansPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(monitorSnapshotProvider);
    final capabilities = ref.watch(monitorCapabilitiesProvider);
    final activeFanCommandId = ref.watch(monitorActiveFanCommandIdProvider);

    return SectionPanel(
      title: 'Fans',
      subtitle: 'Current fan telemetry and manual RPM controls.',
      child: snapshot.fanReadings.isEmpty
          ? const EmptyPanel(
              icon: Icons.wind_power,
              message:
                  'Fan telemetry is not exposed by the bridge yet. The UI is ready for it.',
            )
          : Column(
              children: [
                for (final fan in snapshot.fanReadings) ...[
                  FanControlCard(
                    fan: fan,
                    canControl: capabilities.fanControlEnabled,
                    isBusy: activeFanCommandId == fan.stableId,
                    onAutomatic: () => ref.monitorActions.setFanAutomatic(fan),
                    onManualTargetSelected: (targetRpm) =>
                        ref.monitorActions.setFanTargetRpm(fan, targetRpm),
                  ),
                  if (fan != snapshot.fanReadings.last)
                    const SizedBox(height: 16),
                ],
              ],
            ),
    );
  }
}
