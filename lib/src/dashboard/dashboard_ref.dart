import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mac_fan_tool/src/dashboard/dashboard_view.dart';
import 'package:mac_fan_tool/src/hardware/hardware_controller.dart';

extension DashboardWidgetRefX on WidgetRef {
  MonitorController get monitorActions =>
      read(monitorControllerProvider.notifier);

  DashboardViewController get dashboardViewActions =>
      read(dashboardViewProvider.notifier);
}
