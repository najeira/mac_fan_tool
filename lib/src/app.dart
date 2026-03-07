import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';

import 'package:mac_fan_tool/src/dashboard/dashboard_page.dart';

class MacFanToolApp extends StatelessWidget {
  const MacFanToolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MacosApp(
      title: 'Mac Fan Tool',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: MacosThemeData.light(),
      darkTheme: MacosThemeData.dark(),
      home: const DashboardPage(),
    );
  }
}
