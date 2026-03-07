import 'package:flutter/material.dart';

import 'package:mac_fan_tool/src/dashboard/dashboard_summary.dart';
import 'package:mac_fan_tool/src/dashboard/dashboard_support.dart';
import 'package:mac_fan_tool/src/dashboard/widgets/dashboard_common.dart';
import 'package:mac_fan_tool/src/hardware/hardware_models.dart';

class DetailsView extends StatelessWidget {
  const DetailsView({
    super.key,
    required this.state,
    required this.summary,
    required this.isWide,
  });

  final MonitorState state;
  final DashboardSummary summary;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final cpuPanel = _SensorGroupPanel(
      title: 'CPU Channels',
      subtitle:
          'Individual CPU-related temperature channels. Average ${formatTemperature(summary.cpuAverage)}.',
      sensors: cpuSensors(state.snapshot.sensors),
      emptyMessage:
          'No CPU temperature channels are available from the bridge.',
      emptyIcon: Icons.memory_outlined,
    );

    final gpuPanel = _SensorGroupPanel(
      title: 'GPU Channels',
      subtitle:
          'Individual GPU-related temperature channels. Average ${formatTemperature(summary.gpuAverage)}.',
      sensors: gpuSensors(state.snapshot.sensors),
      emptyMessage:
          'No GPU temperature channels are available from the bridge.',
      emptyIcon: Icons.graphic_eq_outlined,
    );

    final supportingPanel = _SensorGroupPanel(
      title: 'Supporting Thermals',
      subtitle:
          'Memory, storage, power, ambient, and other supporting temperature channels.',
      sensors: supportingSensors(state.snapshot.sensors),
      emptyMessage:
          'No supporting thermal channels are available from the bridge.',
      emptyIcon: Icons.developer_board_outlined,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isWide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: cpuPanel),
              const SizedBox(width: 20),
              Expanded(child: gpuPanel),
            ],
          )
        else ...[
          cpuPanel,
          const SizedBox(height: 20),
          gpuPanel,
        ],
        const SizedBox(height: 20),
        supportingPanel,
      ],
    );
  }
}

class _SensorGroupPanel extends StatelessWidget {
  const _SensorGroupPanel({
    required this.title,
    required this.subtitle,
    required this.sensors,
    required this.emptyMessage,
    required this.emptyIcon,
  });

  final String title;
  final String subtitle;
  final List<SensorReading> sensors;
  final String emptyMessage;
  final IconData emptyIcon;

  @override
  Widget build(BuildContext context) {
    return SectionPanel(
      title: title,
      subtitle: subtitle,
      child: sensors.isEmpty
          ? EmptyPanel(icon: emptyIcon, message: emptyMessage)
          : Column(
              children: [
                for (final sensor in sensors) ...[
                  SensorRow(sensor: sensor),
                  if (sensor != sensors.last) const Divider(height: 24),
                ],
              ],
            ),
    );
  }
}
