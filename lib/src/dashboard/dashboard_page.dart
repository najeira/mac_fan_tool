import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import 'package:mac_fan_tool/src/hardware/hardware_controller.dart';
import 'package:mac_fan_tool/src/hardware/hardware_models.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(monitorControllerProvider);
    final controller = ref.read(monitorControllerProvider.notifier);

    return MacosWindow(
      child: Theme(
        data: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF295A64),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          fontFamily: '.AppleSystemUIFont',
        ),
        child: Material(
          color: Colors.transparent,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[Color(0xFFF4F0E8), Color(0xFFE7EEF1)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 1180;

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(28, 28, 28, 36),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _HeroPanel(
                          state: state,
                          onRefresh: state.isRefreshing
                              ? null
                              : () => controller.refresh(),
                        ),
                        if (state.errorMessage != null) ...[
                          const SizedBox(height: 18),
                          _NoticeBanner(
                            tone: _NoticeTone.error,
                            message: state.errorMessage!,
                          ),
                        ],
                        if (state.lastCommandMessage != null) ...[
                          const SizedBox(height: 18),
                          _NoticeBanner(
                            tone: _NoticeTone.success,
                            message: state.lastCommandMessage!,
                          ),
                        ],
                        if (_hardwareNote(state) case final note?) ...[
                          const SizedBox(height: 18),
                          _NoticeBanner(tone: _NoticeTone.info, message: note),
                        ],
                        const SizedBox(height: 26),
                        _OverviewMetrics(state: state),
                        const SizedBox(height: 24),
                        if (isWide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _SensorsPanel(state: state),
                                    const SizedBox(height: 20),
                                    _HistoryPanel(state: state),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _FansPanel(
                                      state: state,
                                      controller: controller,
                                    ),
                                    const SizedBox(height: 20),
                                    _HardwareBridgePanel(state: state),
                                  ],
                                ),
                              ),
                            ],
                          )
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SensorsPanel(state: state),
                              const SizedBox(height: 20),
                              _FansPanel(state: state, controller: controller),
                              const SizedBox(height: 20),
                              _HistoryPanel(state: state),
                              const SizedBox(height: 20),
                              _HardwareBridgePanel(state: state),
                            ],
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.state, required this.onRefresh});

  final MonitorState state;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final cpuSensor = _selectPrimaryCpuSensor(state.snapshot.sensors);
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
                      'Riverpod dashboard plus Pigeon bridge scaffold for raw thermals and fan control on macOS.',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: foreground.withValues(alpha: 0.82),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _PillChip(
                          label: state.device.model,
                          color: const Color(0xFF24414E),
                          foreground: foreground,
                        ),
                        _PillChip(
                          label: state.capabilities.backend,
                          color: const Color(0xFF1D5C66),
                          foreground: foreground,
                        ),
                        _PillChip(
                          label: _thermalLabel(state.snapshot.thermalState),
                          color: _thermalChipColor(state.snapshot.thermalState),
                          foreground: foreground,
                        ),
                        if (cpuSensor != null)
                          _PillChip(
                            label:
                                '${cpuSensor.value.toStringAsFixed(1)} ${cpuSensor.unit}',
                            color: const Color(0xFF6A4A2A),
                            foreground: foreground,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
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

class _OverviewMetrics extends StatelessWidget {
  const _OverviewMetrics({required this.state});

  final MonitorState state;

  @override
  Widget build(BuildContext context) {
    final cpuSensor = _selectPrimaryCpuSensor(state.snapshot.sensors);

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _MetricCard(
          label: 'CPU Sensor',
          value: cpuSensor == null
              ? 'Pending'
              : '${cpuSensor.value.toStringAsFixed(1)} ${cpuSensor.unit}',
          caption: cpuSensor == null
              ? 'Raw SMC/HID sensor not connected yet'
              : cpuSensor.name,
        ),
        _MetricCard(
          label: 'Fans',
          value: state.snapshot.fans.isEmpty
              ? 'Unavailable'
              : '${state.snapshot.fans.length}',
          caption: state.capabilities.hasFans
              ? 'Reported by the native bridge'
              : 'No active fan telemetry from the backend',
        ),
        _MetricCard(
          label: 'Fan Control',
          value: state.capabilities.supportsFanControl
              ? 'Enabled'
              : 'Read only',
          caption: state.capabilities.supportsFanControl
              ? 'Manual fan commands can be sent'
              : 'Bridge is scaffolded but write path is not wired yet',
        ),
        _MetricCard(
          label: 'Last Sample',
          value: _sampleAge(state.snapshot.capturedAt),
          caption: 'Updated ${_formatSampleTime(state.snapshot.capturedAt)}',
        ),
      ],
    );
  }
}

class _SensorsPanel extends StatelessWidget {
  const _SensorsPanel({required this.state});

  final MonitorState state;

  @override
  Widget build(BuildContext context) {
    return _SectionPanel(
      title: 'Sensors',
      subtitle: 'CPU and thermal channels from the native bridge.',
      child: state.snapshot.sensors.isEmpty
          ? const _EmptyPanel(
              icon: Icons.thermostat,
              message:
                  'Raw sensor values will appear here once the SMC/HID reader is connected.',
            )
          : Column(
              children: [
                for (final sensor in state.snapshot.sensors) ...[
                  _SensorRow(sensor: sensor),
                  if (sensor != state.snapshot.sensors.last)
                    const Divider(height: 24),
                ],
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
    return _SectionPanel(
      title: 'Fans',
      subtitle: 'Manual RPM targets and automatic mode handoff.',
      child: state.snapshot.fans.isEmpty
          ? const _EmptyPanel(
              icon: Icons.wind_power,
              message:
                  'Fan telemetry is not exposed by the bridge yet. The UI is ready for it.',
            )
          : Column(
              children: [
                for (final fan in state.snapshot.fans) ...[
                  FanControlCard(
                    fan: fan,
                    canControl: state.capabilities.supportsFanControl,
                    isBusy: state.activeFanCommandId == fan.id,
                    onAutomatic: () => controller.setFanAutomatic(fan),
                    onManualTargetSelected: (targetRpm) =>
                        controller.setFanTargetRpm(fan, targetRpm),
                  ),
                  if (fan != state.snapshot.fans.last)
                    const SizedBox(height: 16),
                ],
              ],
            ),
    );
  }
}

class _HistoryPanel extends StatelessWidget {
  const _HistoryPanel({required this.state});

  final MonitorState state;

  @override
  Widget build(BuildContext context) {
    final points = _cpuHistory(state.history);

    return _SectionPanel(
      title: 'CPU Temperature History',
      subtitle: 'Rolling history from the polling loop.',
      child: points.length < 2
          ? const _EmptyPanel(
              icon: Icons.show_chart,
              message:
                  'The chart will populate once at least two CPU samples are available.',
            )
          : SizedBox(
              height: 240,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: math.max(1, points.length - 1).toDouble(),
                  minY: _minY(points),
                  maxY: _maxY(points),
                  lineTouchData: const LineTouchData(enabled: false),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: _chartInterval(points),
                    getDrawingHorizontalLine: (_) =>
                        const FlLine(color: Color(0x22354B55), strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 46,
                        interval: _chartInterval(points),
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '${value.toStringAsFixed(0)}°',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: const Color(0xFF50636A)),
                          );
                        },
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      isCurved: true,
                      barWidth: 4,
                      color: const Color(0xFF2C8C7A),
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: const Color(0x332C8C7A),
                      ),
                      spots: [
                        for (final entry in points.asMap().entries)
                          FlSpot(entry.key.toDouble(), entry.value),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _HardwareBridgePanel extends StatelessWidget {
  const _HardwareBridgePanel({required this.state});

  final MonitorState state;

  @override
  Widget build(BuildContext context) {
    return _SectionPanel(
      title: 'Hardware Bridge',
      subtitle: 'Current device identity and native backend capabilities.',
      child: Column(
        children: [
          _KeyValueRow(label: 'Computer', value: state.device.computerName),
          const Divider(height: 24),
          _KeyValueRow(label: 'Model', value: state.device.model),
          const Divider(height: 24),
          _KeyValueRow(label: 'Architecture', value: state.device.architecture),
          const Divider(height: 24),
          _KeyValueRow(label: 'macOS Release', value: state.device.osVersion),
          const Divider(height: 24),
          _KeyValueRow(label: 'Backend', value: state.capabilities.backend),
          const Divider(height: 24),
          _KeyValueRow(
            label: 'Raw Sensors',
            value: state.capabilities.supportsRawSensors
                ? 'Available'
                : 'Not available yet',
          ),
          const Divider(height: 24),
          _KeyValueRow(
            label: 'Fan Control',
            value: state.capabilities.supportsFanControl
                ? 'Writable'
                : 'Disabled',
          ),
        ],
      ),
    );
  }
}

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

class _SectionPanel extends StatelessWidget {
  const _SectionPanel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8EA)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120C141A),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF5A6E75)),
          ),
          const SizedBox(height: 22),
          child,
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.caption,
  });

  final String label;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFBF8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE1E7E9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: const Color(0xFF566A72)),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            caption,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF677B82),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _PillChip extends StatelessWidget {
  const _PillChip({
    required this.label,
    required this.color,
    required this.foreground,
  });

  final String label;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

enum _NoticeTone { info, success, error }

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.tone, required this.message});

  final _NoticeTone tone;
  final String message;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      _NoticeTone.info => const Color(0xFF265C6A),
      _NoticeTone.success => const Color(0xFF1E7C63),
      _NoticeTone.error => const Color(0xFF9A443D),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F4ED),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7DDD1)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF7C6850)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF6E5A45),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SensorRow extends StatelessWidget {
  const _SensorRow({required this.sensor});

  final SensorReading sensor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: _sensorColor(sensor.kind),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sensor.name,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                sensor.id,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: const Color(0xFF647880)),
              ),
            ],
          ),
        ),
        Text(
          '${sensor.value.toStringAsFixed(1)} ${sensor.unit}',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
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

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF5D7078)),
          ),
        ),
        const SizedBox(width: 18),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

String? _hardwareNote(MonitorState state) {
  return state.snapshot.note ?? state.capabilities.note ?? state.device.note;
}

String _thermalLabel(ThermalStateLevel level) {
  switch (level) {
    case ThermalStateLevel.nominal:
      return 'Thermal nominal';
    case ThermalStateLevel.fair:
      return 'Thermal fair';
    case ThermalStateLevel.serious:
      return 'Thermal serious';
    case ThermalStateLevel.critical:
      return 'Thermal critical';
    case ThermalStateLevel.unknown:
      return 'Thermal unknown';
  }
}

Color _thermalChipColor(ThermalStateLevel level) {
  switch (level) {
    case ThermalStateLevel.nominal:
      return const Color(0xFF1E6A5C);
    case ThermalStateLevel.fair:
      return const Color(0xFF866225);
    case ThermalStateLevel.serious:
      return const Color(0xFF9B5B26);
    case ThermalStateLevel.critical:
      return const Color(0xFF8F3F3D);
    case ThermalStateLevel.unknown:
      return const Color(0xFF4B5D66);
  }
}

SensorReading? _selectPrimaryCpuSensor(List<SensorReading> sensors) {
  for (final sensor in sensors) {
    if (sensor.kind == SensorKind.cpu) {
      return sensor;
    }
  }

  return sensors.isEmpty ? null : sensors.first;
}

List<double> _cpuHistory(List<HardwareSnapshot> history) {
  final points = <double>[];

  for (final snapshot in history) {
    final sensor = _selectPrimaryCpuSensor(snapshot.sensors);
    if (sensor != null && sensor.kind == SensorKind.cpu) {
      points.add(sensor.value);
    }
  }

  return points;
}

double _minY(List<double> points) {
  final minimum = points.reduce(math.min);
  return math.max(0, (minimum - 2).floorToDouble());
}

double _maxY(List<double> points) {
  final maximum = points.reduce(math.max);
  return (maximum + 2).ceilToDouble();
}

double _chartInterval(List<double> points) {
  final span = (_maxY(points) - _minY(points)).abs();
  if (span <= 8) {
    return 2;
  }
  if (span <= 20) {
    return 5;
  }
  return 10;
}

String _sampleAge(DateTime capturedAt) {
  if (capturedAt.millisecondsSinceEpoch == 0) {
    return 'Pending';
  }

  final age = DateTime.now().difference(capturedAt);
  if (age.inSeconds < 60) {
    return '${age.inSeconds}s ago';
  }
  if (age.inMinutes < 60) {
    return '${age.inMinutes}m ago';
  }
  return '${age.inHours}h ago';
}

String _formatSampleTime(DateTime capturedAt) {
  if (capturedAt.millisecondsSinceEpoch == 0) {
    return 'not sampled yet';
  }

  final hour = capturedAt.hour.toString().padLeft(2, '0');
  final minute = capturedAt.minute.toString().padLeft(2, '0');
  final second = capturedAt.second.toString().padLeft(2, '0');
  return '$hour:$minute:$second';
}

Color _sensorColor(SensorKind kind) {
  switch (kind) {
    case SensorKind.cpu:
      return const Color(0xFF2C8C7A);
    case SensorKind.gpu:
      return const Color(0xFF9B5B26);
    case SensorKind.memory:
      return const Color(0xFF5D6AC3);
    case SensorKind.ambient:
      return const Color(0xFF6A6B3F);
    case SensorKind.other:
      return const Color(0xFF5D7078);
  }
}
