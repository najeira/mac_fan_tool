import 'dart:math' as math;

import 'package:flutter/material.dart';

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

  final FanReading fan;
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
    final span = math.max(1, widget.fan.maximumRpm - widget.fan.minimumRpm);
    final divisions = math.max(1, span ~/ 100);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE0E6E8)),
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
                      widget.fan.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${widget.fan.currentRpm} RPM now • ${widget.fan.minimumRpm}-${widget.fan.maximumRpm} RPM range',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF566A72),
                      ),
                    ),
                  ],
                ),
              ),
              _ModeBadge(mode: widget.fan.mode),
            ],
          ),
          const SizedBox(height: 18),
          Slider(
            value: _targetRpm.clamp(
              widget.fan.minimumRpm.toDouble(),
              widget.fan.maximumRpm.toDouble(),
            ),
            min: widget.fan.minimumRpm.toDouble(),
            max: widget.fan.maximumRpm.toDouble(),
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
                ).textTheme.bodySmall?.copyWith(color: const Color(0xFF44575F)),
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

  int _resolvedTarget(FanReading fan) {
    return fan.targetRpm ?? fan.currentRpm;
  }
}

class _ModeBadge extends StatelessWidget {
  const _ModeBadge({required this.mode});

  final FanControlMode mode;

  @override
  Widget build(BuildContext context) {
    final isManual = mode == FanControlMode.manual;
    final color = isManual ? const Color(0xFF7A5134) : const Color(0xFF2E6B5F);

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
