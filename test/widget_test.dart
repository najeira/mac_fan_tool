import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mac_fan_tool/main.dart';
import 'package:mac_fan_tool/src/app.dart';
import 'package:mac_fan_tool/src/dashboard/dashboard_state.dart';
import 'package:mac_fan_tool/src/dashboard/widgets/dashboard_common.dart';
import 'package:mac_fan_tool/src/hardware/hardware_models.dart';

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

    expect(find.text('Preparing hardware monitor'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets(
    'shows transient notices as snackbars instead of inline banners',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            monitorTransientNoticeProvider.overrideWith(
              (ref) => const MonitorNotice(
                tone: MonitorNoticeTone.success,
                message: 'Fan command completed.',
              ),
            ),
          ],
          child: const MacFanToolApp(),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Fan command completed.'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(NoticeBanner),
          matching: find.text('Fan command completed.'),
        ),
        findsNothing,
      );
    },
  );
}
