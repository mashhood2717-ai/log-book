import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_logbook/screens/login_screen.dart';
import 'package:trip_logbook/widgets/animations.dart';
import 'package:trip_logbook/widgets/brand.dart';

void main() {
  testWidgets('BrandMark plays its entrance and settles', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: BrandMark(width: 200)))));
    await tester.pumpAndSettle();
    expect(find.byType(BrandMark), findsOneWidget);
    expect(tester.getSize(find.byType(CustomPaint).last).width, 200);
  });

  testWidgets('Login screen lays out on a small phone without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    // Background blobs loop forever, so pump a fixed time instead of settling.
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Sign in'), findsWidgets);
    expect(find.byType(BrandWordmark), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CountUp ends on the exact value', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: CountUp(value: 1234, format: (v) => 'n=$v')));
    await tester.pumpAndSettle();
    expect(find.text('n=1234'), findsOneWidget);
  });
}
