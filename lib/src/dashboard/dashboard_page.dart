import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import 'package:mac_fan_tool/src/dashboard/dashboard_debug.dart';
import 'package:mac_fan_tool/src/dashboard/dashboard_state.dart';
import 'package:mac_fan_tool/src/dashboard/dashboard_view.dart';
import 'package:mac_fan_tool/src/dashboard/views/details_view.dart';
import 'package:mac_fan_tool/src/dashboard/views/overview_view.dart';
import 'package:mac_fan_tool/src/dashboard/views/system_view.dart';
import 'package:mac_fan_tool/src/dashboard/widgets/dashboard_common.dart';
import 'package:mac_fan_tool/src/dashboard/widgets/dashboard_hero_panel.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
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
        child: const Material(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[Color(0xFFF4F0E8), Color(0xFFE7EEF1)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(child: _DashboardLayout()),
          ),
        ),
      ),
    );
  }
}

class _DashboardLayout extends ConsumerWidget {
  const _DashboardLayout();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debugEnabled = ref.watch(dashboardDebugEnabledProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1180;
        return ProviderScope(
          overrides: [dashboardIsWideProvider.overrideWithValue(isWide)],
          child: ListView(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 36),
            children: [
              if (debugEnabled) const DashboardDebugPanel(),
              const DashboardHeroPanel(),
              const _DashboardStatusBanners(),
              const SizedBox(height: 26),
              const _DashboardBody(),
            ],
          ),
        );
      },
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(dashboardViewProvider);

    switch (view) {
      case DashboardView.overview:
        return const OverviewView();
      case DashboardView.details:
        return const DetailsView();
      case DashboardView.system:
        return const SystemView();
    }
  }
}

class _DashboardStatusBanners extends ConsumerWidget {
  const _DashboardStatusBanners();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final errorMessage = ref.watch(monitorErrorMessageProvider);
    final lastCommandMessage = ref.watch(monitorLastCommandMessageProvider);
    final hardwareNote = ref.watch(dashboardHardwareNoteProvider);

    final children = [
      if (errorMessage != null)
        Padding(
          padding: const EdgeInsets.only(top: 18),
          child: NoticeBanner(tone: NoticeTone.error, message: errorMessage),
        ),
      if (lastCommandMessage != null)
        Padding(
          padding: const EdgeInsets.only(top: 18),
          child: NoticeBanner(
            tone: NoticeTone.success,
            message: lastCommandMessage,
          ),
        ),
      if (hardwareNote != null)
        Padding(
          padding: const EdgeInsets.only(top: 18),
          child: NoticeBanner(tone: NoticeTone.info, message: hardwareNote),
        ),
    ];
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}
