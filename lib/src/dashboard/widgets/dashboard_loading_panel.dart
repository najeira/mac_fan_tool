import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mac_fan_tool/src/dashboard/dashboard_state.dart';
import 'package:mac_fan_tool/src/dashboard/widgets/dashboard_common.dart';

class DashboardLoadingPanel extends ConsumerWidget {
  const DashboardLoadingPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBootstrapping = ref.watch(monitorIsBootstrappingProvider);
    final hasInitialSnapshot = ref.watch(monitorHasInitialSnapshotProvider);
    final device = ref.watch(monitorDeviceProvider);
    final capabilities = ref.watch(monitorCapabilitiesProvider);

    return SectionPanel(
      title: 'Preparing hardware monitor',
      subtitle: isBootstrapping
          ? 'Connecting to the native bridge and reading device capabilities.'
          : 'The dashboard will appear once the first live sensor sample is available.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFF7FAFB),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE0E8EB)),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    isBootstrapping
                        ? 'Initializing device profile and capabilities.'
                        : 'Waiting for the first telemetry sample from the native bridge.',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: const Color(0xFF28434B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _LoadingStepRow(
            label: 'Device profile',
            value: isBootstrapping ? 'Reading' : device.model,
            isComplete: !isBootstrapping,
          ),
          const SizedBox(height: 12),
          _LoadingStepRow(
            label: 'Native backend',
            value: isBootstrapping
                ? 'Connecting'
                : (capabilities.backend ?? 'unavailable'),
            isComplete: !isBootstrapping,
          ),
          const SizedBox(height: 12),
          _LoadingStepRow(
            label: 'First telemetry sample',
            value: hasInitialSnapshot ? 'Ready' : 'Pending',
            isComplete: hasInitialSnapshot,
          ),
        ],
      ),
    );
  }
}

class _LoadingStepRow extends StatelessWidget {
  const _LoadingStepRow({
    required this.label,
    required this.value,
    required this.isComplete,
  });

  final String label;
  final String value;
  final bool isComplete;

  @override
  Widget build(BuildContext context) {
    final accent = isComplete
        ? const Color(0xFF1F7A62)
        : const Color(0xFF8A6E46);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(
            isComplete ? Icons.check_circle : Icons.schedule,
            color: accent,
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: const Color(0xFF314951),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
