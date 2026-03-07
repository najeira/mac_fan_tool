import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import 'package:mac_fan_tool/src/dashboard/dashboard_colors.dart';
import 'package:mac_fan_tool/src/dashboard/dashboard_state.dart';
import 'package:mac_fan_tool/src/dashboard/dashboard_view.dart';
import 'package:mac_fan_tool/src/dashboard/views/details_view.dart';
import 'package:mac_fan_tool/src/dashboard/views/overview_view.dart';
import 'package:mac_fan_tool/src/dashboard/views/system_view.dart';
import 'package:mac_fan_tool/src/dashboard/widgets/dashboard_common.dart';
import 'package:mac_fan_tool/src/dashboard/widgets/dashboard_hero_panel.dart';
import 'package:mac_fan_tool/src/dashboard/widgets/dashboard_loading_panel.dart';
import 'package:mac_fan_tool/src/dashboard/widgets/responsive_dashboard_scope.dart';
import 'package:mac_fan_tool/src/hardware/hardware_controller.dart';
import 'package:mac_fan_tool/src/hardware/hardware_models.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MacosWindow(
      child: Theme(
        data: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: DashboardColors.seed,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          fontFamily: '.AppleSystemUIFont',
        ),
        child: const Material(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  DashboardColors.backgroundStart,
                  DashboardColors.backgroundEnd,
                ],
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
    final showLoadingPanel = ref.watch(showLoadingPanelProvider);

    return ResponsiveDashboardScope(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(28, 44, 28, 36),
        children: [
          // const DebugPanel(),
          const _TransientNoticeSection(),
          const _PersistentStatusSection(),
          const SizedBox(height: 18),
          if (showLoadingPanel) ...const [LoadingPanel()] else ...const [
            HeroPanel(),
            SizedBox(height: 26),
            _DashboardBody(),
          ],
        ],
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(viewProvider);

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

class _TransientNoticeSection extends ConsumerWidget {
  const _TransientNoticeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(monitorTransientNoticeProvider);
    if (notice == null) {
      return const SizedBox.shrink();
    }

    return NoticeBanner(
      tone: switch (notice.tone) {
        MonitorNoticeTone.info => NoticeTone.info,
        MonitorNoticeTone.success => NoticeTone.success,
        MonitorNoticeTone.error => NoticeTone.error,
      },
      message: notice.message,
      onDismiss: ref
          .read(monitorControllerProvider.notifier)
          .dismissTransientNotice,
    );
  }
}

class _PersistentStatusSection extends ConsumerWidget {
  const _PersistentStatusSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banners = ref.watch(persistentStatusBannersProvider);
    if (banners.isEmpty) {
      return const SizedBox.shrink();
    }

    return SeparatedColumn(
      separator: const SizedBox(height: 18),
      children: [
        for (final banner in banners)
          NoticeBanner(tone: banner.$1, message: banner.$2),
      ],
    );
  }
}
