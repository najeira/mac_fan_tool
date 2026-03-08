import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mac_fan_tool/src/dashboard/dashboard_colors.dart';
import 'package:mac_fan_tool/src/dashboard/dashboard_ref.dart';
import 'package:mac_fan_tool/src/dashboard/dashboard_state.dart';
import 'package:mac_fan_tool/src/dashboard/dashboard_support.dart';
import 'package:mac_fan_tool/src/dashboard/dashboard_view.dart';
import 'package:mac_fan_tool/src/dashboard/widgets/dashboard_common.dart';
import 'package:mac_fan_tool/src/hardware/hardware_models.dart';

class HeroPanel extends StatelessWidget {
  const HeroPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: DashboardColors.heroSurface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: DashboardColors.heroShadow,
            blurRadius: 28,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _ViewSwitcher(),
            ],
          ),
          const SizedBox(height: 18),
          const _HeroStatusChips(),
        ],
      ),
    );
  }
}

class _ViewSwitcher extends ConsumerWidget {
  const _ViewSwitcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedView = ref.watch(viewProvider);

    return SegmentedButton<DashboardView>(
      segments: const [
        ButtonSegment<DashboardView>(
          value: DashboardView.overview,
          icon: Icon(Icons.dashboard_outlined),
          label: Text('Overview'),
        ),
        ButtonSegment<DashboardView>(
          value: DashboardView.details,
          icon: Icon(Icons.thermostat_outlined),
          label: Text('Details'),
        ),
        ButtonSegment<DashboardView>(
          value: DashboardView.system,
          icon: Icon(Icons.memory_outlined),
          label: Text('System'),
        ),
      ],
      selected: <DashboardView>{selectedView},
      showSelectedIcon: false,
      multiSelectionEnabled: false,
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return DashboardColors.heroControlSelected;
          }
          return DashboardColors.heroControlIdle;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return DashboardColors.heroControlForeground;
          }
          return Colors.white;
        }),
        side: const WidgetStatePropertyAll(
          BorderSide(color: DashboardColors.heroControlBorder),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      onSelectionChanged: (selection) {
        if (selection.isNotEmpty) {
          ref.viewActions.setView(selection.first);
        }
      },
    );
  }
}

class _HeroStatusChips extends StatelessWidget {
  const _HeroStatusChips();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [_OverallTemperatureChip(), _FanSummaryChip()],
    );
  }
}

class _OverallTemperatureChip extends ConsumerWidget {
  const _OverallTemperatureChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overallTemperature = ref.watch(
      summaryProvider.select((summary) => summary.overallTemperature),
    );
    final thermalLevel = ref.watch(
      monitorSnapshotProvider.select((snapshot) => snapshot.thermalLevel),
    );

    return PillChip(
      icon: Icons.device_thermostat,
      label: formatTemperature(overallTemperature),
      color: thermalChipColor(thermalLevel),
      foreground: Theme.of(context).colorScheme.onPrimary,
    );
  }
}

class _FanSummaryChip extends ConsumerWidget {
  const _FanSummaryChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fanSummary = ref.watch(fanSummaryProvider);

    return PillChip(
      icon: Icons.wind_power,
      label: formatFanSummary(fanSummary),
      color: fanSummaryChipColor(fanSummary),
      foreground: Theme.of(context).colorScheme.onPrimary,
    );
  }
}
