import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:mac_fan_tool/src/dashboard/dashboard_colors.dart';
import 'package:mac_fan_tool/src/hardware/hardware_models.dart';

class FanControlCard extends StatefulWidget {
  const FanControlCard({
    super.key,
    required this.fan,
    required this.canControl,
    required this.isBusy,
    required this.onAutomatic,
    required this.onManualTargetSelected,
  });

  final FanReadingData fan;
  final bool canControl;
  final bool isBusy;
  final VoidCallback onAutomatic;
  final ValueChanged<int> onManualTargetSelected;

  @override
  State<FanControlCard> createState() => _FanControlCardState();
}

class _FanControlCardState extends State<FanControlCard> {
  late double _targetRpm;

  @override
  void initState() {
    super.initState();
    _targetRpm = _resolvedTarget(widget.fan).toDouble();
  }

  @override
  void didUpdateWidget(covariant FanControlCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.fan.currentRpm != widget.fan.currentRpm ||
        oldWidget.fan.targetRpm != widget.fan.targetRpm ||
        oldWidget.fan.mode != widget.fan.mode) {
      _targetRpm = _resolvedTarget(widget.fan).toDouble();
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = !widget.canControl || widget.isBusy;
    final span = math.max(
      1,
      widget.fan.safeMaximumRpm - widget.fan.safeMinimumRpm,
    );
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
                      widget.fan.displayName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${widget.fan.safeCurrentRpm} RPM now • ${widget.fan.safeMinimumRpm}-${widget.fan.safeMaximumRpm} RPM range',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: DashboardColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              _ModeBadge(mode: widget.fan.normalizedMode),
            ],
          ),
          const SizedBox(height: 18),
          Slider(
            value: _targetRpm.clamp(
              widget.fan.safeMinimumRpm.toDouble(),
              widget.fan.safeMaximumRpm.toDouble(),
            ),
            min: widget.fan.safeMinimumRpm.toDouble(),
            max: widget.fan.safeMaximumRpm.toDouble(),
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
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(
                  color: DashboardColors.textTarget,
                ),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: disabled ? null : widget.onAutomatic,
                child: const Text('Automatic'),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: disabled
                    ? null
                    : () => widget.onManualTargetSelected(_targetRpm.round()),
                child: Text(widget.isBusy ? 'Applying...' : 'Apply Manual RPM'),
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
