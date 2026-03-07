import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mac_fan_tool/src/dashboard/dashboard_state.dart';
import 'package:mac_fan_tool/src/dashboard/widgets/fan_control_card.dart';
import 'package:mac_fan_tool/src/hardware/hardware_models.dart';

void main() {
  testWidgets(
    'keeps the draft slider value during refresh until telemetry catches up',
    (tester) async {
      const fanId = 'fan-1';
      final fanProvider = NotifierProvider<_TestFanNotifier, FanReadingData?>(
        _TestFanNotifier.new,
      );
      final container = ProviderContainer(
        overrides: [
          fanReadingProvider(
            fanId,
          ).overrideWith((ref) => ref.watch(fanProvider)),
          monitorCapabilitiesProvider.overrideWith(
            (ref) => HardwareCapabilitiesData(
              supportsRawSensors: true,
              supportsFanControl: true,
              hasFans: true,
            ),
          ),
          monitorActiveFanCommandIdsProvider.overrideWith(
            (ref) => const <String>{},
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: FanControlCard(fanId: fanId)),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Target 2000 RPM'), findsOneWidget);

      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChanged!(3000);
      await tester.pump();

      expect(find.textContaining('Pending'), findsOneWidget);

      container.read(fanProvider.notifier).replace(target: 2000, current: 2050);
      await tester.pump();

      expect(find.text('Current 2000 RPM -> Pending 3000 RPM'), findsOneWidget);

      container.read(fanProvider.notifier).replace(target: 3000, current: 2400);
      await tester.pump();

      expect(find.text('Target 3000 RPM'), findsOneWidget);
    },
  );
}

class _TestFanNotifier extends Notifier<FanReadingData?> {
  @override
  FanReadingData? build() {
    return _fan(target: 2000);
  }

  void replace({required int target, int current = 2000}) {
    state = _fan(target: target, current: current);
  }
}

FanReadingData _fan({required int target, int current = 2000}) {
  return FanReadingData(
    id: 'fan-1',
    name: 'System fan',
    currentRpm: current,
    minimumRpm: 1000,
    maximumRpm: 4000,
    targetRpm: target,
    mode: FanModeData.manual,
  );
}
