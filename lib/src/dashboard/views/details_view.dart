import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mac_fan_tool/src/dashboard/dashboard_state.dart';
import 'package:mac_fan_tool/src/dashboard/dashboard_support.dart';
import 'package:mac_fan_tool/src/dashboard/widgets/adaptive_panel_layout.dart';
import 'package:mac_fan_tool/src/dashboard/widgets/dashboard_common.dart';
import 'package:mac_fan_tool/src/hardware/hardware_models.dart';

class DetailsView extends StatelessWidget {
  const DetailsView({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdaptivePanelLayout(
      children: [
        _CpuSensorPanel(),
        _GpuSensorPanel(),
        _SupportingSensorPanel(),
      ],
    );
  }
}

class _CpuSensorPanel extends ConsumerWidget {
  const _CpuSensorPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sensors = ref.watch(
      monitorSnapshotProvider.select(
        (snapshot) => cpuSensors(snapshot.sensorReadings),
      ),
    );
    final cpuAverage = ref.watch(
      summaryProvider.select((summary) => summary.cpuAverage),
    );

    return _SensorGroupPanel(
      title: 'CPU Channels',
      subtitle:
          'Individual CPU-related temperature channels. Average ${formatTemperature(cpuAverage)}.',
      sensors: sensors,
      emptyMessage:
          'No CPU temperature channels are available from the bridge.',
      emptyIcon: Icons.memory_outlined,
    );
  }
}

class _GpuSensorPanel extends ConsumerWidget {
  const _GpuSensorPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sensors = ref.watch(
      monitorSnapshotProvider.select(
        (snapshot) => gpuSensors(snapshot.sensorReadings),
      ),
    );
    final gpuAverage = ref.watch(
      summaryProvider.select((summary) => summary.gpuAverage),
    );

    return _SensorGroupPanel(
      title: 'GPU Channels',
      subtitle:
          'Individual GPU-related temperature channels. Average ${formatTemperature(gpuAverage)}.',
      sensors: sensors,
      emptyMessage:
          'No GPU temperature channels are available from the bridge.',
      emptyIcon: Icons.graphic_eq_outlined,
    );
  }
}

class _SupportingSensorPanel extends ConsumerWidget {
  const _SupportingSensorPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sensors = ref.watch(
      monitorSnapshotProvider.select(
        (snapshot) => supportingSensors(snapshot.sensorReadings),
      ),
    );

    return _SensorGroupPanel(
      title: 'Supporting Thermals',
      subtitle:
          'Memory, storage, power, ambient, and other supporting temperature channels.',
      sensors: sensors,
      emptyMessage:
          'No supporting thermal channels are available from the bridge.',
      emptyIcon: Icons.developer_board_outlined,
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
  final List<SensorReadingData> sensors;
  final String emptyMessage;
  final IconData emptyIcon;

  @override
  Widget build(BuildContext context) {
    return SectionPanel(
      title: title,
      subtitle: subtitle,
      child: sensors.isEmpty
          ? EmptyPanel(icon: emptyIcon, message: emptyMessage)
          : SeparatedColumn(
              separator: const Divider(height: 24),
              children: [
                for (final sensor in sensors) SensorRow(sensor: sensor),
              ],
            ),
    );
  }
}
