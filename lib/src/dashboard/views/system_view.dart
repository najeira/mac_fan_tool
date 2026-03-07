import 'package:flutter/material.dart';

import 'package:mac_fan_tool/src/dashboard/dashboard_summary.dart';
import 'package:mac_fan_tool/src/dashboard/dashboard_support.dart';
import 'package:mac_fan_tool/src/dashboard/widgets/dashboard_common.dart';
import 'package:mac_fan_tool/src/dashboard/widgets/fan_control_card.dart';
import 'package:mac_fan_tool/src/hardware/hardware_controller.dart';
import 'package:mac_fan_tool/src/hardware/hardware_models.dart';

class SystemView extends StatelessWidget {
  const SystemView({
    super.key,
    required this.state,
    required this.summary,
    required this.controller,
    required this.isWide,
  });

  final MonitorState state;
  final DashboardSummary summary;
  final MonitorController controller;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final infoPanel = _SystemInfoPanel(state: state, summary: summary);
    final fansPanel = _FansPanel(state: state, controller: controller);

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
      children: [infoPanel, const SizedBox(height: 20), fansPanel],
    );
  }
}

class _SystemInfoPanel extends StatelessWidget {
  const _SystemInfoPanel({required this.state, required this.summary});

  final MonitorState state;
  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    return SectionPanel(
      title: 'Hardware Bridge',
      subtitle:
          'Device identity, backend status, and the amount of data currently visible to the dashboard.',
      child: Column(
        children: [
          KeyValueRow(label: 'Computer', value: state.device.computerName),
          const Divider(height: 24),
          KeyValueRow(label: 'Model', value: state.device.model),
          const Divider(height: 24),
          KeyValueRow(label: 'Architecture', value: state.device.architecture),
          const Divider(height: 24),
          KeyValueRow(label: 'macOS Release', value: state.device.osVersion),
          const Divider(height: 24),
          KeyValueRow(label: 'Backend', value: state.capabilities.backendLabel),
          const Divider(height: 24),
          KeyValueRow(
            label: 'Raw Sensors',
            value: state.capabilities.rawSensorsEnabled
                ? '${summary.sensorCount} channels'
                : 'Not available yet',
          ),
          const Divider(height: 24),
          KeyValueRow(
            label: 'Fans',
            value: state.capabilities.fanTelemetryAvailable
                ? '${state.snapshot.fanReadings.length} reported'
                : 'Unavailable',
          ),
          const Divider(height: 24),
          KeyValueRow(
            label: 'Fan Control',
            value: state.capabilities.fanControlEnabled
                ? 'Writable'
                : 'Read only',
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

class _FansPanel extends StatelessWidget {
  const _FansPanel({required this.state, required this.controller});

  final MonitorState state;
  final MonitorController controller;

  @override
  Widget build(BuildContext context) {
    return SectionPanel(
      title: 'Fans',
      subtitle: 'Current fan telemetry and manual RPM controls.',
      child: state.snapshot.fanReadings.isEmpty
          ? const EmptyPanel(
              icon: Icons.wind_power,
              message:
                  'Fan telemetry is not exposed by the bridge yet. The UI is ready for it.',
            )
          : Column(
              children: [
                for (final fan in state.snapshot.fanReadings) ...[
                  FanControlCard(
                    fan: fan,
                    canControl: state.capabilities.fanControlEnabled,
                    isBusy: state.activeFanCommandId == fan.stableId,
                    onAutomatic: () => controller.setFanAutomatic(fan),
                    onManualTargetSelected: (targetRpm) =>
                        controller.setFanTargetRpm(fan, targetRpm),
                  ),
                  if (fan != state.snapshot.fanReadings.last)
                    const SizedBox(height: 16),
                ],
              ],
            ),
    );
  }
}
