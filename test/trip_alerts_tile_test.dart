import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_logbook/main.dart';
import 'package:trip_logbook/models.dart';
import 'package:trip_logbook/services/trip_alerts.dart';

void main() {
  Future<void> pump(WidgetTester t, Profile me) async {
    await t.pumpWidget(MaterialApp(
        theme: appTheme(Brightness.light),
        home: Scaffold(body: TripAlerts.settingsTile(me))));
  }

  final admin = Profile(id: 'a', fullName: 'Boss', role: 'admin');
  final driver = Profile(id: 'd', fullName: 'Ali', role: 'driver');

  testWidgets('shows a registration error with Try again', (t) async {
    TripAlerts.status.value = 'Could not register: SERVICE_NOT_AVAILABLE';
    await pump(t, admin);
    expect(find.text('Could not register: SERVICE_NOT_AVAILABLE'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('registered phone shows a tick and no retry', (t) async {
    TripAlerts.status.value = 'This phone is registered ✓';
    await pump(t, admin);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('drivers see why, and cannot switch it on', (t) async {
    TripAlerts.status.value = 'Only for admins';
    await pump(t, driver);
    expect(find.text('Only for admins'), findsOneWidget);
    expect(t.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged, isNull);
  });
}
