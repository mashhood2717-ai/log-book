import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_logbook/main.dart';
import 'package:trip_logbook/services/reminders.dart';
import 'package:trip_logbook/widgets/notification_banner.dart';

void main() {
  Future<void> pump(WidgetTester t) async {
    await t.pumpWidget(MaterialApp(
        theme: appTheme(Brightness.light),
        home: const Scaffold(body: NotificationBanner())));
    await t.pumpAndSettle();
  }

  tearDown(() {
    Reminders.enabled.value = true;
    Reminders.permission.value = null;
  });

  testWidgets('shows when reminders are on but notifications are blocked',
      (t) async {
    Reminders.permission.value = false;
    await pump(t);
    expect(find.text('Notifications are off'), findsOneWidget);
    expect(find.text('Allow'), findsOneWidget);
  });

  testWidgets('hidden when notifications are allowed or unknown', (t) async {
    Reminders.permission.value = true;
    await pump(t);
    expect(find.text('Notifications are off'), findsNothing);
    Reminders.permission.value = null;
    await t.pumpAndSettle();
    expect(find.text('Notifications are off'), findsNothing);
  });

  testWidgets('hidden when the person turned reminders off', (t) async {
    Reminders.permission.value = false;
    Reminders.enabled.value = false;
    await pump(t);
    expect(find.text('Notifications are off'), findsNothing);
  });

  testWidgets('appears and disappears live', (t) async {
    Reminders.permission.value = true;
    await pump(t);
    Reminders.permission.value = false;
    await t.pumpAndSettle();
    expect(find.text('Notifications are off'), findsOneWidget);
    Reminders.permission.value = true;
    await t.pumpAndSettle();
    expect(find.text('Notifications are off'), findsNothing);
  });
}
