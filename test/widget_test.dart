import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mac_fan_tool/main.dart';

void main() {
  testWidgets('renders the hardware dashboard shell', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('CPU Avg'), findsOneWidget);
    expect(find.text('Thermal Trend'), findsOneWidget);
  });
}
