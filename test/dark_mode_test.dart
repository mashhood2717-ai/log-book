import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_logbook/main.dart';
import 'package:trip_logbook/models.dart';
import 'package:trip_logbook/screens/edit_trip_screen.dart';
import 'package:trip_logbook/screens/login_screen.dart';
import 'package:trip_logbook/services/db.dart';
import 'package:trip_logbook/services/theme_settings.dart';
import 'package:trip_logbook/widgets/brand.dart';

void main() {
  test('dark theme carries the dark colour set', () {
    final t = appTheme(Brightness.dark);
    expect(t.brightness, Brightness.dark);
    expect(t.extension<AppColors>(), same(AppColors.dark));
    expect(t.scaffoldBackgroundColor, AppColors.dark.page);
    expect(appTheme(Brightness.light).extension<AppColors>(),
        same(AppColors.light));
  });

  test('every appearance option has a label and icon', () {
    for (final m in ThemeMode.values) {
      expect(ThemeSettings.label(m), isNotEmpty);
      expect(ThemeSettings.icon(m), isNotNull);
    }
  });

  Future<void> pumpDark(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        theme: appTheme(Brightness.light),
        darkTheme: appTheme(Brightness.dark),
        themeMode: ThemeMode.dark,
        home: home));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('login renders in dark mode with light text', (tester) async {
    await pumpDark(tester, const LoginScreen());
    expect(tester.takeException(), isNull);
    final title = tester.widget<Text>(find.text('Sign in').first);
    expect(title.style?.color, AppColors.dark.ink);
  });

  testWidgets('edit trip renders in dark mode', (tester) async {
    Db.me = Profile(id: 'a', fullName: 'Boss', role: 'admin');
    addTearDown(() => Db.me = null);
    final now = DateTime.now();
    await pumpDark(
        tester,
        EditTripScreen(
            trip: Trip.fromMap({
          'id': 1,
          'driver_id': 'd',
          'vehicle_id': 1,
          'status': 'completed',
          'start_time': now.subtract(const Duration(hours: 3)).toUtc().toIso8601String(),
          'end_time': now.subtract(const Duration(hours: 1)).toUtc().toIso8601String(),
          'start_mileage': 100,
          'end_mileage': 150,
          'purpose': 'p',
          'destination': 'd',
        })));
    expect(tester.takeException(), isNull);
    expect(find.text('End mileage (km)'), findsOneWidget);
  });
}
