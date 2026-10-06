import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_logbook/models.dart';
import 'package:trip_logbook/screens/edit_trip_screen.dart';
import 'package:trip_logbook/services/db.dart';

Trip _trip({Duration? endedAgo}) {
  final now = DateTime.now();
  final ended = endedAgo == null ? null : now.subtract(endedAgo);
  return Trip.fromMap({
    'id': 42,
    'driver_id': 'someone-else',
    'vehicle_id': 1,
    'status': ended == null ? 'ongoing' : 'completed',
    'start_time': (ended ?? now)
        .subtract(const Duration(hours: 2))
        .toUtc()
        .toIso8601String(),
    'end_time': ended?.toUtc().toIso8601String(),
    'start_mileage': 1000,
    'end_mileage': ended == null ? null : 1080,
    'purpose': 'Site visit',
    'destination': 'Nowshera',
    'fuel_litres': 12.5,
    'vehicles': {'reg_no': 'LEB-1234'},
    'profiles': {'full_name': 'Ali'},
  });
}

void main() {
  // Admin, so canEdit doesn't need a signed-in Supabase user.
  setUp(() => Db.me = Profile(id: 'admin', fullName: 'Boss', role: 'admin'));
  tearDown(() => Db.me = null);

  group('24-hour edit window', () {
    test('open trip is editable, no time limit', () {
      final t = _trip();
      expect(Db.canEdit(t), isTrue);
      expect(Db.editTimeLeft(t), isNull);
    });

    test('finished 23h ago is editable with ~1h left', () {
      final t = _trip(endedAgo: const Duration(hours: 23));
      expect(Db.canEdit(t), isTrue);
      expect(Db.editTimeLeft(t)!.inMinutes, inInclusiveRange(59, 60));
    });

    test('finished 25h ago is locked', () {
      expect(Db.canEdit(_trip(endedAgo: const Duration(hours: 25))), isFalse);
    });
  });

  Future<void> pumpEdit(WidgetTester tester, Trip t) async {
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: EditTripScreen(trip: t)));
    await tester.pumpAndSettle();
  }

  testWidgets('finished trip shows all correctable fields, prefilled',
      (tester) async {
    await pumpEdit(tester, _trip(endedAgo: const Duration(hours: 1)));
    expect(find.text('End mileage (km)'), findsOneWidget);
    expect(find.text('1080'), findsOneWidget);
    expect(find.text('12.5'), findsOneWidget);
    expect(find.textContaining('You can edit this trip for another'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('open trip hides end-of-trip fields', (tester) async {
    await pumpEdit(tester, _trip());
    expect(find.text('End mileage (km)'), findsNothing);
    expect(find.text('Purpose'), findsOneWidget);
  });

  testWidgets('end mileage below start is rejected', (tester) async {
    await pumpEdit(tester, _trip(endedAgo: const Duration(hours: 1)));
    await tester.enterText(
        find.widgetWithText(TextFormField, 'End mileage (km)'), '900');
    // The button is below the fold on a small phone; scroll it into view.
    await tester.scrollUntilVisible(find.text('Save changes'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Save changes'));
    await tester.pump();
    expect(find.text('Cannot be less than start mileage'), findsOneWidget);
  });
}
