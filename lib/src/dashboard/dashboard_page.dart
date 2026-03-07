import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import 'package:mac_fan_tool/src/dashboard/dashboard_summary.dart';
import 'package:mac_fan_tool/src/dashboard/dashboard_support.dart';
import 'package:mac_fan_tool/src/dashboard/dashboard_view.dart';
import 'package:mac_fan_tool/src/dashboard/views/details_view.dart';
import 'package:mac_fan_tool/src/dashboard/views/overview_view.dart';
import 'package:mac_fan_tool/src/dashboard/views/system_view.dart';
import 'package:mac_fan_tool/src/dashboard/widgets/dashboard_common.dart';
import 'package:mac_fan_tool/src/dashboard/widgets/dashboard_hero_panel.dart';
import 'package:mac_fan_tool/src/hardware/hardware_controller.dart';
import 'package:mac_fan_tool/src/hardware/hardware_models.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  DashboardView _selectedView = DashboardView.overview;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(monitorControllerProvider);
    final controller = ref.read(monitorControllerProvider.notifier);
    final summary = DashboardSummary.fromSnapshot(state.snapshot);

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
                        DashboardHeroPanel(
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
                          NoticeBanner(
                            tone: NoticeTone.error,
                            message: state.errorMessage!,
                          ),
                        ],
                        if (state.lastCommandMessage != null) ...[
                          const SizedBox(height: 18),
                          NoticeBanner(
                            tone: NoticeTone.success,
                            message: state.lastCommandMessage!,
                          ),
                        ],
                        if (hardwareNote(state) case final note?) ...[
                          const SizedBox(height: 18),
                          NoticeBanner(tone: NoticeTone.info, message: note),
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

  final DashboardView view;
  final MonitorState state;
  final DashboardSummary summary;
  final MonitorController controller;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    switch (view) {
      case DashboardView.overview:
        return OverviewView(state: state, summary: summary, isWide: isWide);
      case DashboardView.details:
        return DetailsView(state: state, summary: summary, isWide: isWide);
      case DashboardView.system:
        return SystemView(
          state: state,
          summary: summary,
          controller: controller,
          isWide: isWide,
        );
    }
  }
}
