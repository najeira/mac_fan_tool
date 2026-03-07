import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

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
                        const DashboardHeroPanel(),
                        const _DashboardStatusBanners(),
                        const SizedBox(height: 26),
                        _DashboardBody(isWide: isWide),
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

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.isWide});

  final bool isWide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(dashboardViewProvider);

    switch (view) {
      case DashboardView.overview:
        return OverviewView(isWide: isWide);
      case DashboardView.details:
        return DetailsView(isWide: isWide);
      case DashboardView.system:
        return SystemView(isWide: isWide);
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

    if (errorMessage == null &&
        lastCommandMessage == null &&
        hardwareNote == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (errorMessage != null) ...[
          const SizedBox(height: 18),
          NoticeBanner(tone: NoticeTone.error, message: errorMessage),
        ],
        if (lastCommandMessage != null) ...[
          const SizedBox(height: 18),
          NoticeBanner(tone: NoticeTone.success, message: lastCommandMessage),
        ],
        if (hardwareNote != null) ...[
          const SizedBox(height: 18),
          NoticeBanner(tone: NoticeTone.info, message: hardwareNote),
        ],
      ],
    );
  }
}
