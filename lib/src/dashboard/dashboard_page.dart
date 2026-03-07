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

import 'dashboard_debug.dart';

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
        child: const ScaffoldMessenger(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: DecoratedBox(
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
          const DebugPanel(),
          const _TransientNoticeToastHost(),
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

class _TransientNoticeToastHost extends ConsumerStatefulWidget {
  const _TransientNoticeToastHost();

  @override
  ConsumerState<_TransientNoticeToastHost> createState() =>
      _TransientNoticeToastHostState();
}

class _TransientNoticeToastHostState
    extends ConsumerState<_TransientNoticeToastHost> {
  late final ProviderSubscription<MonitorNotice?> _noticeSubscription;

  @override
  void initState() {
    super.initState();
    _noticeSubscription = ref.listenManual<MonitorNotice?>(
      monitorTransientNoticeProvider,
      (previous, next) => _syncNotice(next),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _syncNotice(ref.read(monitorTransientNoticeProvider));
    });
  }

  @override
  void dispose() {
    _noticeSubscription.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }

  void _syncNotice(MonitorNotice? notice) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) {
        return;
      }

      messenger.hideCurrentSnackBar();

      if (notice == null) {
        return;
      }

      final accentColor = switch (notice.tone) {
        MonitorNoticeTone.info => DashboardColors.info,
        MonitorNoticeTone.success => DashboardColors.success,
        MonitorNoticeTone.error => DashboardColors.error,
      };

      final icon = switch (notice.tone) {
        MonitorNoticeTone.info => Icons.info_outline,
        MonitorNoticeTone.success => Icons.check_circle_outline,
        MonitorNoticeTone.error => Icons.error_outline,
      };

      final controller = messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: ref.read(transientNoticeDurationProvider),
          elevation: 0,
          backgroundColor: Colors.transparent,
          padding: EdgeInsets.zero,
          margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          content: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: accentColor.withValues(alpha: 0.24)),
              boxShadow: const [
                BoxShadow(
                  color: DashboardColors.panelShadow,
                  blurRadius: 18,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(icon, color: accentColor, size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    notice.message,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: DashboardColors.textStrong,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: ref
                      .read(monitorControllerProvider.notifier)
                      .dismissTransientNotice,
                  icon: Icon(Icons.close, color: accentColor, size: 18),
                  splashRadius: 18,
                  tooltip: 'Dismiss',
                ),
              ],
            ),
          ),
        ),
      );
      controller.closed.then((_) {
        if (!mounted) {
          return;
        }
        if (identical(ref.read(monitorTransientNoticeProvider), notice)) {
          ref.read(monitorControllerProvider.notifier).dismissTransientNotice();
        }
      });
    });
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
