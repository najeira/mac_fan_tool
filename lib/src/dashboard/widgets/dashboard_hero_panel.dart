import 'package:flutter/material.dart';

import 'package:mac_fan_tool/src/dashboard/dashboard_summary.dart';
import 'package:mac_fan_tool/src/dashboard/dashboard_support.dart';
import 'package:mac_fan_tool/src/dashboard/dashboard_view.dart';
import 'package:mac_fan_tool/src/dashboard/widgets/dashboard_common.dart';
import 'package:mac_fan_tool/src/hardware/hardware_models.dart';

class DashboardHeroPanel extends StatelessWidget {
  const DashboardHeroPanel({
    super.key,
    required this.state,
    required this.summary,
    required this.selectedView,
    required this.onViewSelected,
    required this.onRefresh,
  });

  final MonitorState state;
  final DashboardSummary summary;
  final DashboardView selectedView;
  final ValueChanged<DashboardView> onViewSelected;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final foreground = Theme.of(context).colorScheme.onPrimary;

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xFF15242E),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x220C141A),
            blurRadius: 28,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mac Fan Tool',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Overview first, sensor detail second. Switch between aggregate thermals, per-channel temperatures, and system information.',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: foreground.withValues(alpha: 0.82),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _DashboardViewSwitcher(
                      selectedView: selectedView,
                      onViewSelected: onViewSelected,
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        PillChip(
                          label: state.device.model,
                          color: const Color(0xFF24414E),
                          foreground: foreground,
                        ),
                        PillChip(
                          label: state.capabilities.backendLabel,
                          color: const Color(0xFF1D5C66),
                          foreground: foreground,
                        ),
                        PillChip(
                          label: thermalLabel(state.snapshot.thermalLevel),
                          color: thermalChipColor(state.snapshot.thermalLevel),
                          foreground: foreground,
                        ),
                        PillChip(
                          label: compositeChipLabel(summary.overallTemperature),
                          color: const Color(0xFF6A4A2A),
                          foreground: foreground,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FilledButton.icon(
                    onPressed: onRefresh,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFDBE9EB),
                      foregroundColor: const Color(0xFF0F1D24),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),
                    ),
                    icon: Icon(state.isRefreshing ? Icons.sync : Icons.refresh),
                    label: Text(state.isRefreshing ? 'Refreshing' : 'Refresh'),
                  ),
                  const SizedBox(height: 18),
                  _PrimaryMetricPanel(summary: summary),
                ],
              ),
            ],
          ),
          if (state.isBootstrapping) ...[
            const SizedBox(height: 22),
            const LinearProgressIndicator(
              minHeight: 5,
              backgroundColor: Color(0x401A3038),
            ),
          ],
        ],
      ),
    );
  }
}

class _DashboardViewSwitcher extends StatelessWidget {
  const _DashboardViewSwitcher({
    required this.selectedView,
    required this.onViewSelected,
  });

  final DashboardView selectedView;
  final ValueChanged<DashboardView> onViewSelected;

  @override
  Widget build(BuildContext context) {
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
            return const Color(0xFFDBE9EB);
          }
          return const Color(0xFF24414E);
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const Color(0xFF0F1D24);
          }
          return Colors.white;
        }),
        side: const WidgetStatePropertyAll(
          BorderSide(color: Color(0xFF3A5361)),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      onSelectionChanged: (selection) {
        if (selection.isNotEmpty) {
          onViewSelected(selection.first);
        }
      },
    );
  }
}

class _PrimaryMetricPanel extends StatelessWidget {
  const _PrimaryMetricPanel({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0x1AE7EEF1),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x335A7380)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Composite Thermal',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            formatTemperature(summary.overallTemperature),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            summary.overallCaption,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.72),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
