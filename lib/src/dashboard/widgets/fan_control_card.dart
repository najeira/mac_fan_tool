import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mac_fan_tool/src/dashboard/dashboard_colors.dart';
import 'package:mac_fan_tool/src/dashboard/dashboard_ref.dart';
import 'package:mac_fan_tool/src/dashboard/dashboard_state.dart';
import 'package:mac_fan_tool/src/hardware/hardware_models.dart';

class FanControlCard extends ConsumerStatefulWidget {
  const FanControlCard({super.key, required this.fanId});

  final String fanId;

  @override
  ConsumerState<FanControlCard> createState() => _FanControlCardState();
}

class _FanControlCardState extends ConsumerState<FanControlCard> {
  late double _targetRpm;

  @override
  void initState() {
    super.initState();
    final fan = ref.read(fanReadingProvider(widget.fanId));
    _targetRpm = fan == null ? 0 : _resolvedTarget(fan).toDouble();
  }

  @override
  void didUpdateWidget(covariant FanControlCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fanId != widget.fanId) {
      final fan = ref.read(fanReadingProvider(widget.fanId));
      _targetRpm = fan == null ? 0 : _resolvedTarget(fan).toDouble();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<FanReadingData?>(fanReadingProvider(widget.fanId), (
      previous,
      next,
    ) {
      if (!mounted || next == null) {
        return;
      }

      final didTelemetryChange =
          previous == null ||
          previous.currentRpm != next.currentRpm ||
          previous.targetRpm != next.targetRpm ||
          previous.mode != next.mode;
      if (!didTelemetryChange) {
        return;
      }

      final nextTargetRpm = _resolvedTarget(next).toDouble();
      if (_targetRpm == nextTargetRpm) {
        return;
      }

      setState(() {
        _targetRpm = nextTargetRpm;
      });
    });

    final fan = ref.watch(fanReadingProvider(widget.fanId));
    if (fan == null) {
      return const SizedBox.shrink();
    }

    final canControl = ref.watch(
      monitorCapabilitiesProvider.select(
        (capabilities) => capabilities.fanControlEnabled,
      ),
    );
    final isBusy = ref.watch(monitorActiveFanCommandIdProvider) == fan.stableId;
    final disabled = !canControl || isBusy;
    final span = math.max(1, fan.safeMaximumRpm - fan.safeMinimumRpm);
    final divisions = math.max(1, span ~/ 100);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: DashboardColors.controlBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fan.displayName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${fan.safeCurrentRpm} RPM now • ${fan.safeMinimumRpm}-${fan.safeMaximumRpm} RPM range',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: DashboardColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              _ModeBadge(mode: fan.normalizedMode),
            ],
          ),
          const SizedBox(height: 18),
          Slider(
            value: _targetRpm.clamp(
              fan.safeMinimumRpm.toDouble(),
              fan.safeMaximumRpm.toDouble(),
            ),
            min: fan.safeMinimumRpm.toDouble(),
            max: fan.safeMaximumRpm.toDouble(),
            divisions: divisions,
            label: '${_targetRpm.round()} RPM',
            onChanged: disabled
                ? null
                : (value) {
                    setState(() {
                      _targetRpm = value;
                    });
                  },
          ),
          Row(
            children: [
              Text(
                'Target ${_targetRpm.round()} RPM',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: DashboardColors.textTarget,
                ),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: disabled
                    ? null
                    : () => ref.monitorActions.setFanAutomatic(fan),
                child: const Text('Automatic'),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: disabled
                    ? null
                    : () => ref.monitorActions.setFanTargetRpm(
                        fan,
                        _targetRpm.round(),
                      ),
                child: Text(isBusy ? 'Applying...' : 'Apply Manual RPM'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  int _resolvedTarget(FanReadingData fan) {
    return fan.safeTargetRpm ?? fan.safeCurrentRpm;
  }
}

class _ModeBadge extends StatelessWidget {
  const _ModeBadge({required this.mode});

  final FanModeData mode;

  @override
  Widget build(BuildContext context) {
    final isManual = mode == FanModeData.manual;
    final color = isManual
        ? DashboardColors.fanManual
        : DashboardColors.fanAutomatic;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isManual ? 'Manual' : 'Automatic',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
