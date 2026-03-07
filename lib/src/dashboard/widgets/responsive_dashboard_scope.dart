import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mac_fan_tool/src/dashboard/dashboard_state.dart';

class ResponsiveDashboardScope extends StatelessWidget {
  const ResponsiveDashboardScope({
    super.key,
    required this.child,
    this.wideBreakpoint = 1180,
  });

  final Widget child;
  final double wideBreakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= wideBreakpoint;
        return ProviderScope(
          overrides: [isWideProvider.overrideWithValue(isWide)],
          child: child,
        );
      },
    );
  }
}
