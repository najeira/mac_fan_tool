import 'package:flutter_test/flutter_test.dart';

import 'package:mac_fan_tool/main.dart';

void main() {
  testWidgets('renders the hardware dashboard shell', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Mac Fan Tool'), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Composite Thermal'), findsOneWidget);
  });
}
