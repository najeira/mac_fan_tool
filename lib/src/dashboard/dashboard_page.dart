import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import 'package:mac_fan_tool/src/hardware/hardware_controller.dart';
import 'package:mac_fan_tool/src/hardware/hardware_models.dart';

enum _DashboardView { overview, details, system }

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  _DashboardView _selectedView = _DashboardView.overview;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(monitorControllerProvider);
    final controller = ref.read(monitorControllerProvider.notifier);
    final summary = _DashboardSummary.fromSnapshot(state.snapshot);

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
                          summary: summary,
                          selectedView: _selectedView,
                          onViewSelected: (view) {
                            setState(() {
                              _selectedView = view;
                            });
                          },
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
                        _DashboardBody(
                          view: _selectedView,
                          state: state,
                          summary: summary,
                          controller: controller,
                          isWide: isWide,
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

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.view,
    required this.state,
    required this.summary,
    required this.controller,
    required this.isWide,
  });

  final _DashboardView view;
  final MonitorState state;
  final _DashboardSummary summary;
  final MonitorController controller;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    switch (view) {
      case _DashboardView.overview:
        return _OverviewView(state: state, summary: summary, isWide: isWide);
      case _DashboardView.details:
        return _DetailsView(state: state, summary: summary, isWide: isWide);
      case _DashboardView.system:
        return _SystemView(
          state: state,
          summary: summary,
          controller: controller,
          isWide: isWide,
        );
    }
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.state,
    required this.summary,
    required this.selectedView,
    required this.onViewSelected,
    required this.onRefresh,
  });

  final MonitorState state;
  final _DashboardSummary summary;
  final _DashboardView selectedView;
  final ValueChanged<_DashboardView> onViewSelected;
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
                    _ViewSwitcher(
                      selectedView: selectedView,
                      onViewSelected: onViewSelected,
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
                        _PillChip(
                          label: _summaryChipLabel(summary),
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

class _ViewSwitcher extends StatelessWidget {
  const _ViewSwitcher({
    required this.selectedView,
    required this.onViewSelected,
  });

  final _DashboardView selectedView;
  final ValueChanged<_DashboardView> onViewSelected;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_DashboardView>(
      segments: const [
        ButtonSegment<_DashboardView>(
          value: _DashboardView.overview,
          icon: Icon(Icons.dashboard_outlined),
          label: Text('Overview'),
        ),
        ButtonSegment<_DashboardView>(
          value: _DashboardView.details,
          icon: Icon(Icons.thermostat_outlined),
          label: Text('Details'),
        ),
        ButtonSegment<_DashboardView>(
          value: _DashboardView.system,
          icon: Icon(Icons.memory_outlined),
          label: Text('System'),
        ),
      ],
      selected: <_DashboardView>{selectedView},
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
        final next = selection.firstOrNull;
        if (next != null) {
          onViewSelected(next);
        }
      },
    );
  }
}

class _PrimaryMetricPanel extends StatelessWidget {
  const _PrimaryMetricPanel({required this.summary});

  final _DashboardSummary summary;

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
            _formatTemperature(summary.overallTemperature),
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

class _OverviewView extends StatelessWidget {
  const _OverviewView({
    required this.state,
    required this.summary,
    required this.isWide,
  });

  final MonitorState state;
  final _DashboardSummary summary;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _MetricCard(
        label: 'CPU Avg',
        value: _formatTemperature(summary.cpuAverage),
        caption: _sensorCountCaption(summary.cpuSensorCount, 'CPU'),
      ),
      _MetricCard(
        label: 'GPU Avg',
        value: _formatTemperature(summary.gpuAverage),
        caption: _sensorCountCaption(summary.gpuSensorCount, 'GPU'),
      ),
      _MetricCard(
        label: 'Power Avg',
        value: _formatTemperature(summary.powerAverage),
        caption: _sensorCountCaption(summary.powerSensorCount, 'power'),
      ),
      _MetricCard(
        label: 'Disk Avg',
        value: _formatTemperature(summary.diskAverage),
        caption: _sensorCountCaption(summary.diskSensorCount, 'disk'),
      ),
      _MetricCard(
        label: 'Memory Avg',
        value: _formatTemperature(summary.memoryAverage),
        caption: _sensorCountCaption(summary.memorySensorCount, 'memory'),
      ),
      _MetricCard(
        label: 'Last Sample',
        value: _sampleAge(state.snapshot.capturedAt),
        caption: 'Updated ${_formatSampleTime(state.snapshot.capturedAt)}',
      ),
    ];

    final trendPanel = _ThermalTrendPanel(state: state);
    final breakdownPanel = _CategoryBreakdownPanel(summary: summary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 16, runSpacing: 16, children: cards),
        const SizedBox(height: 24),
        if (isWide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: trendPanel),
              const SizedBox(width: 20),
              Expanded(child: breakdownPanel),
            ],
          )
        else ...[
          trendPanel,
          const SizedBox(height: 20),
          breakdownPanel,
        ],
      ],
    );
  }
}

class _ThermalTrendPanel extends StatelessWidget {
  const _ThermalTrendPanel({required this.state});

  final MonitorState state;

  @override
  Widget build(BuildContext context) {
    final summaries = [
      for (final snapshot in state.history)
        _DashboardSummary.fromSnapshot(snapshot),
    ];
    final series = _buildTrendSeries(summaries);

    return _SectionPanel(
      title: 'Thermal Trend',
      subtitle:
          'Composite, CPU average, and GPU average over the recent polling window.',
      child: series.every((item) => item.spots.length < 2)
          ? const _EmptyPanel(
              icon: Icons.show_chart,
              message:
                  'The chart appears once at least two aggregated samples are available.',
            )
          : Column(
              children: [
                SizedBox(
                  height: 240,
                  child: LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: _trendMaxX(series),
                      minY: _trendMinY(series),
                      maxY: _trendMaxY(series),
                      lineTouchData: const LineTouchData(enabled: false),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: _trendInterval(series),
                        getDrawingHorizontalLine: (_) => const FlLine(
                          color: Color(0x22354B55),
                          strokeWidth: 1,
                        ),
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
                            reservedSize: 48,
                            interval: _trendInterval(series),
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
                        for (final item in series)
                          LineChartBarData(
                            isCurved: true,
                            barWidth: 3,
                            color: item.color,
                            dotData: const FlDotData(show: false),
                            belowBarData: item.fillColor == null
                                ? BarAreaData(show: false)
                                : BarAreaData(
                                    show: true,
                                    color: item.fillColor,
                                  ),
                            spots: item.spots,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 14,
                  runSpacing: 10,
                  children: [
                    for (final item in series.where(
                      (series) => series.spots.isNotEmpty,
                    ))
                      _LegendChip(color: item.color, label: item.label),
                  ],
                ),
              ],
            ),
    );
  }
}

class _CategoryBreakdownPanel extends StatelessWidget {
  const _CategoryBreakdownPanel({required this.summary});

  final _DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final categories = [
      _SummaryCategory(
        label: 'CPU',
        value: summary.cpuAverage,
        count: summary.cpuSensorCount,
        color: _sensorColor(SensorKind.cpu),
      ),
      _SummaryCategory(
        label: 'GPU',
        value: summary.gpuAverage,
        count: summary.gpuSensorCount,
        color: _sensorColor(SensorKind.gpu),
      ),
      _SummaryCategory(
        label: 'Power',
        value: summary.powerAverage,
        count: summary.powerSensorCount,
        color: const Color(0xFF7A5B34),
      ),
      _SummaryCategory(
        label: 'Disk',
        value: summary.diskAverage,
        count: summary.diskSensorCount,
        color: const Color(0xFF546A36),
      ),
      _SummaryCategory(
        label: 'Memory',
        value: summary.memoryAverage,
        count: summary.memorySensorCount,
        color: _sensorColor(SensorKind.memory),
      ),
      _SummaryCategory(
        label: 'Ambient',
        value: summary.ambientAverage,
        count: summary.ambientSensorCount,
        color: _sensorColor(SensorKind.ambient),
      ),
    ];

    final maxValue = categories
        .map((category) => category.value ?? 0)
        .fold<double>(0, math.max);

    return _SectionPanel(
      title: 'Category Snapshot',
      subtitle:
          'Balanced averages by thermal domain so one large sensor family does not dominate the overview.',
      child: Column(
        children: [
          for (final category in categories) ...[
            _CategoryBarRow(
              category: category,
              maxValue: maxValue <= 0 ? 1 : maxValue,
            ),
            if (category != categories.last) const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

class _DetailsView extends StatelessWidget {
  const _DetailsView({
    required this.state,
    required this.summary,
    required this.isWide,
  });

  final MonitorState state;
  final _DashboardSummary summary;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final cpuSensors = _cpuSensors(state.snapshot.sensors);
    final gpuSensors = _gpuSensors(state.snapshot.sensors);
    final supportingSensors = _supportingSensors(state.snapshot.sensors);

    final cpuPanel = _SensorGroupPanel(
      title: 'CPU Channels',
      subtitle:
          'Individual CPU-related temperature channels. Average ${_formatTemperature(summary.cpuAverage)}.',
      sensors: cpuSensors,
      emptyMessage:
          'No CPU temperature channels are available from the bridge.',
      emptyIcon: Icons.memory_outlined,
    );

    final gpuPanel = _SensorGroupPanel(
      title: 'GPU Channels',
      subtitle:
          'Individual GPU-related temperature channels. Average ${_formatTemperature(summary.gpuAverage)}.',
      sensors: gpuSensors,
      emptyMessage:
          'No GPU temperature channels are available from the bridge.',
      emptyIcon: Icons.graphic_eq_outlined,
    );

    final supportingPanel = _SensorGroupPanel(
      title: 'Supporting Thermals',
      subtitle:
          'Memory, storage, power, ambient, and other supporting temperature channels.',
      sensors: supportingSensors,
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

class _SystemView extends StatelessWidget {
  const _SystemView({
    required this.state,
    required this.summary,
    required this.controller,
    required this.isWide,
  });

  final MonitorState state;
  final _DashboardSummary summary;
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
  final _DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    return _SectionPanel(
      title: 'Hardware Bridge',
      subtitle:
          'Device identity, backend status, and the amount of data currently visible to the dashboard.',
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
                ? '${summary.sensorCount} channels'
                : 'Not available yet',
          ),
          const Divider(height: 24),
          _KeyValueRow(
            label: 'Fans',
            value: state.capabilities.hasFans
                ? '${state.snapshot.fans.length} reported'
                : 'Unavailable',
          ),
          const Divider(height: 24),
          _KeyValueRow(
            label: 'Fan Control',
            value: state.capabilities.supportsFanControl
                ? 'Writable'
                : 'Read only',
          ),
          const Divider(height: 24),
          _KeyValueRow(
            label: 'Composite Thermal',
            value: _formatTemperature(summary.overallTemperature),
          ),
        ],
      ),
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
    return _SectionPanel(
      title: title,
      subtitle: subtitle,
      child: sensors.isEmpty
          ? _EmptyPanel(icon: emptyIcon, message: emptyMessage)
          : Column(
              children: [
                for (final sensor in sensors) ...[
                  _SensorRow(sensor: sensor),
                  if (sensor != sensors.last) const Divider(height: 24),
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
      subtitle: 'Current fan telemetry and manual RPM controls.',
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
      width: 220,
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

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: const Color(0xFF314951),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryBarRow extends StatelessWidget {
  const _CategoryBarRow({required this.category, required this.maxValue});

  final _SummaryCategory category;
  final double maxValue;

  @override
  Widget build(BuildContext context) {
    final ratio = category.value == null ? 0.0 : (category.value! / maxValue);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 92,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                category.label,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                category.count <= 0
                    ? 'No sensors'
                    : '${category.count} sensors',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: const Color(0xFF61757D)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio.clamp(0, 1),
              minHeight: 12,
              backgroundColor: const Color(0xFFE7ECEE),
              color: category.color,
            ),
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 92,
          child: Text(
            _formatTemperature(category.value),
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

class _TrendSeries {
  const _TrendSeries({
    required this.label,
    required this.color,
    required this.spots,
    this.fillColor,
  });

  final String label;
  final Color color;
  final List<FlSpot> spots;
  final Color? fillColor;
}

class _SummaryCategory {
  const _SummaryCategory({
    required this.label,
    required this.value,
    required this.count,
    required this.color,
  });

  final String label;
  final double? value;
  final int count;
  final Color color;
}

class _DashboardSummary {
  const _DashboardSummary({
    required this.overallTemperature,
    required this.cpuAverage,
    required this.gpuAverage,
    required this.powerAverage,
    required this.diskAverage,
    required this.memoryAverage,
    required this.ambientAverage,
    required this.sensorCount,
    required this.cpuSensorCount,
    required this.gpuSensorCount,
    required this.powerSensorCount,
    required this.diskSensorCount,
    required this.memorySensorCount,
    required this.ambientSensorCount,
    required this.overallCaption,
  });

  factory _DashboardSummary.fromSnapshot(HardwareSnapshot snapshot) {
    final sensors = snapshot.sensors;
    final cpu = _cpuSensors(sensors);
    final gpu = _gpuSensors(sensors);
    final power = _powerSensors(sensors);
    final disk = _diskSensors(sensors);
    final memory = _memorySensors(sensors);
    final ambient = _ambientSensors(sensors);

    final cpuAverage = _mean(cpu.map((sensor) => sensor.value));
    final gpuAverage = _mean(gpu.map((sensor) => sensor.value));
    final powerAverage = _mean(power.map((sensor) => sensor.value));
    final diskAverage = _mean(disk.map((sensor) => sensor.value));
    final memoryAverage = _mean(memory.map((sensor) => sensor.value));
    final ambientAverage = _mean(ambient.map((sensor) => sensor.value));

    final categoryAverages = [
      cpuAverage,
      gpuAverage,
      powerAverage,
      diskAverage,
      memoryAverage,
      ambientAverage,
    ].whereType<double>();

    final overallTemperature = _mean(categoryAverages);
    final fallbackOverall =
        overallTemperature ?? _mean(sensors.map((sensor) => sensor.value));

    return _DashboardSummary(
      overallTemperature: fallbackOverall,
      cpuAverage: cpuAverage,
      gpuAverage: gpuAverage,
      powerAverage: powerAverage,
      diskAverage: diskAverage,
      memoryAverage: memoryAverage,
      ambientAverage: ambientAverage,
      sensorCount: sensors.length,
      cpuSensorCount: cpu.length,
      gpuSensorCount: gpu.length,
      powerSensorCount: power.length,
      diskSensorCount: disk.length,
      memorySensorCount: memory.length,
      ambientSensorCount: ambient.length,
      overallCaption: categoryAverages.isEmpty
          ? 'Waiting for enough temperature channels to calculate a balanced system reading.'
          : 'Balanced mean of CPU, GPU, power, disk, memory, and ambient groups when available.',
    );
  }

  final double? overallTemperature;
  final double? cpuAverage;
  final double? gpuAverage;
  final double? powerAverage;
  final double? diskAverage;
  final double? memoryAverage;
  final double? ambientAverage;

  final int sensorCount;
  final int cpuSensorCount;
  final int gpuSensorCount;
  final int powerSensorCount;
  final int diskSensorCount;
  final int memorySensorCount;
  final int ambientSensorCount;
  final String overallCaption;
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

String _summaryChipLabel(_DashboardSummary summary) {
  if (summary.overallTemperature == null) {
    return 'Composite pending';
  }
  return 'Composite ${summary.overallTemperature!.toStringAsFixed(1)} C';
}

String _formatTemperature(double? value) {
  if (value == null) {
    return 'Unavailable';
  }
  return '${value.toStringAsFixed(1)} C';
}

String _sensorCountCaption(int count, String category) {
  if (count <= 0) {
    return 'No $category channels available yet';
  }
  return '$count $category channel${count == 1 ? '' : 's'} aggregated';
}

List<_TrendSeries> _buildTrendSeries(List<_DashboardSummary> summaries) {
  List<FlSpot> buildSpots(double? Function(_DashboardSummary) selector) {
    final spots = <FlSpot>[];
    for (final entry in summaries.asMap().entries) {
      final value = selector(entry.value);
      if (value != null) {
        spots.add(FlSpot(entry.key.toDouble(), value));
      }
    }
    return spots;
  }

  return [
    _TrendSeries(
      label: 'Composite',
      color: const Color(0xFF2C8C7A),
      fillColor: const Color(0x222C8C7A),
      spots: buildSpots((summary) => summary.overallTemperature),
    ),
    _TrendSeries(
      label: 'CPU Avg',
      color: const Color(0xFF265C6A),
      spots: buildSpots((summary) => summary.cpuAverage),
    ),
    _TrendSeries(
      label: 'GPU Avg',
      color: const Color(0xFF9B5B26),
      spots: buildSpots((summary) => summary.gpuAverage),
    ),
  ];
}

double _trendMinY(List<_TrendSeries> series) {
  final values = [
    for (final item in series) ...item.spots.map((spot) => spot.y),
  ];
  if (values.isEmpty) {
    return 0;
  }
  final minimum = values.reduce(math.min);
  return math.max(0, (minimum - 2).floorToDouble());
}

double _trendMaxY(List<_TrendSeries> series) {
  final values = [
    for (final item in series) ...item.spots.map((spot) => spot.y),
  ];
  if (values.isEmpty) {
    return 100;
  }
  final maximum = values.reduce(math.max);
  return (maximum + 2).ceilToDouble();
}

double _trendMaxX(List<_TrendSeries> series) {
  final values = [
    for (final item in series) ...item.spots.map((spot) => spot.x),
  ];
  if (values.isEmpty) {
    return 1;
  }
  return math.max(1, values.reduce(math.max));
}

double _trendInterval(List<_TrendSeries> series) {
  final span = (_trendMaxY(series) - _trendMinY(series)).abs();
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

List<SensorReading> _cpuSensors(List<SensorReading> sensors) {
  return [
    for (final sensor in sensors)
      if (sensor.kind == SensorKind.cpu) sensor,
  ];
}

List<SensorReading> _gpuSensors(List<SensorReading> sensors) {
  return [
    for (final sensor in sensors)
      if (sensor.kind == SensorKind.gpu) sensor,
  ];
}

List<SensorReading> _memorySensors(List<SensorReading> sensors) {
  return [
    for (final sensor in sensors)
      if (sensor.kind == SensorKind.memory) sensor,
  ];
}

List<SensorReading> _ambientSensors(List<SensorReading> sensors) {
  return [
    for (final sensor in sensors)
      if (sensor.kind == SensorKind.ambient) sensor,
  ];
}

List<SensorReading> _diskSensors(List<SensorReading> sensors) {
  return [
    for (final sensor in sensors)
      if (_matchesCategory(sensor, const ['ssd', 'nand', 'disk'])) sensor,
  ];
}

List<SensorReading> _powerSensors(List<SensorReading> sensors) {
  return [
    for (final sensor in sensors)
      if (sensor.kind == SensorKind.other &&
          _matchesCategory(sensor, const [
            'power',
            'supply',
            'pmgr',
            'manager',
            'pmu',
            'calibration',
          ]))
        sensor,
  ];
}

List<SensorReading> _supportingSensors(List<SensorReading> sensors) {
  final cpuIds = _cpuSensors(sensors).map((sensor) => sensor.id).toSet();
  final gpuIds = _gpuSensors(sensors).map((sensor) => sensor.id).toSet();

  return [
    for (final sensor in sensors)
      if (!cpuIds.contains(sensor.id) && !gpuIds.contains(sensor.id)) sensor,
  ];
}

bool _matchesCategory(SensorReading sensor, List<String> keywords) {
  final text = '${sensor.name} ${sensor.id}'.toLowerCase();
  for (final keyword in keywords) {
    if (text.contains(keyword)) {
      return true;
    }
  }
  return false;
}

double? _mean(Iterable<double> values) {
  final list = values.where((value) => value.isFinite).toList();
  if (list.isEmpty) {
    return null;
  }
  return list.reduce((a, b) => a + b) / list.length;
}
