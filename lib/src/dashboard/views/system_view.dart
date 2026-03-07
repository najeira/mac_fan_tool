import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mac_fan_tool/src/dashboard/dashboard_state.dart';
import 'package:mac_fan_tool/src/dashboard/dashboard_support.dart';
import 'package:mac_fan_tool/src/dashboard/widgets/adaptive_panel_layout.dart';
import 'package:mac_fan_tool/src/dashboard/widgets/dashboard_common.dart';
import 'package:mac_fan_tool/src/dashboard/widgets/fan_control_card.dart';
import 'package:mac_fan_tool/src/hardware/hardware_models.dart';

class SystemView extends StatelessWidget {
  const SystemView({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdaptivePanelLayout(
      children: [_SystemInfoPanel(), _FansPanel()],
    );
  }
}

class _SystemInfoPanel extends ConsumerWidget {
  const _SystemInfoPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(monitorDeviceProvider);
    final capabilities = ref.watch(monitorCapabilitiesProvider);
    final summary = ref.watch(summaryProvider);
    final fanReadingsLength = ref.watch(
      monitorSnapshotProvider.select((snapshot) => snapshot.fanReadings.length),
    );

    return SectionPanel(
      title: 'Hardware Bridge',
      subtitle:
          'Device identity, backend status, and the amount of data currently visible to the dashboard.',
      child: SeparatedColumn(
        separator: const Divider(height: 24),
        children: [
          KeyValueRow(label: 'Computer', value: device.computerName),
          KeyValueRow(label: 'Model', value: device.model),
          KeyValueRow(label: 'Architecture', value: device.architecture),
          KeyValueRow(label: 'macOS Release', value: device.osVersion),
          KeyValueRow(label: 'Backend', value: capabilities.backendLabel),
          KeyValueRow(
            label: 'Raw Sensors',
            value: capabilities.rawSensorsEnabled
                ? '${summary.sensorCount} channels'
                : 'Not available yet',
          ),
          KeyValueRow(
            label: 'Fans',
            value: capabilities.fanTelemetryAvailable
                ? '$fanReadingsLength devices'
                : 'Unavailable',
          ),
          KeyValueRow(
            label: 'Fan Control',
            value: capabilities.fanControlEnabled ? 'Writable' : 'Read only',
          ),
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
    final fanReadings = ref.watch(
      monitorSnapshotProvider.select((snapshot) => snapshot.fanReadings),
    );

    return SectionPanel(
      title: 'Fans',
      subtitle: 'Current fan telemetry and manual RPM controls.',
      child: fanReadings.isEmpty
          ? const EmptyPanel(
              icon: Icons.wind_power,
              message:
                  'Fan telemetry is not exposed by the bridge yet. The UI is ready for it.',
            )
          : SeparatedColumn(
              separator: const SizedBox(height: 16),
              children: [
                for (final fan in fanReadings)
                  FanControlCard(fanId: fan.stableId),
              ],
            ),
    );
  }
}
