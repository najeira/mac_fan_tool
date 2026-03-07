import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mac_fan_tool/src/dashboard/dashboard_debug.dart';
import 'package:mac_fan_tool/src/dashboard/dashboard_view.dart';
import 'package:mac_fan_tool/src/hardware/hardware_controller.dart';

extension WidgetRefActionsX on WidgetRef {
  MonitorController get monitorActions =>
      read(monitorControllerProvider.notifier);

  ViewController get viewActions => read(viewProvider.notifier);

  DebugFlagsController get debugFlagsActions => read(debugFlagsProvider.notifier);
}
