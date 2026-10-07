import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:trip_logbook/models.dart';
import 'package:trip_logbook/services/reminders.dart';

void main() {
  // Pakistan is UTC+5 all year (no daylight saving).
  DateTime utc(int h, int m) => DateTime.utc(2026, 10, 7, h, m);

  test('reminders are 11:00 AM and 5:00 PM', () {
    expect(Reminders.slots.map((s) => s.label), ['11:00 AM', '5:00 PM']);
  });

  test('next 11 AM PKT later the same day', () {
    final t = Reminders.nextPkt(11, 0, now: utc(3, 0)); // 08:00 PKT
    expect(t.location.name, 'Asia/Karachi');
    expect([t.day, t.hour, t.minute], [7, 11, 0]);
    expect(t.toUtc(), utc(6, 0)); // 11:00 PKT = 06:00 UTC
  });

  test('after 11 AM PKT it moves to tomorrow', () {
    final t = Reminders.nextPkt(11, 0, now: utc(6, 0)); // exactly 11:00 PKT
    expect([t.day, t.hour], [8, 11]);
  });

  test('5 PM PKT regardless of the phone time zone', () {
    // 10:00 UTC = 15:00 PKT -> still today 17:00 PKT = 12:00 UTC
    final t = Reminders.nextPkt(17, 0, now: utc(10, 0));
    expect(t.toUtc(), utc(12, 0));
    expect(t, isA<tz.TZDateTime>());
  });

  test('message mentions the open trip', () {
    final trip = Trip.fromMap({
      'id': 1, 'driver_id': 'd', 'vehicle_id': 1, 'status': 'ongoing',
      'start_time': '2026-10-07T04:00:00Z', 'start_mileage': 1,
      'purpose': 'p', 'destination': 'Nowshera',
      'vehicles': {'reg_no': 'LEB-1234'},
    });
    final (title, body) = Reminders.message(Reminders.slots[1], trip);
    expect(title, 'Back yet?');
    expect(body, contains('LEB-1234 → Nowshera'));

    final (t2, b2) = Reminders.message(Reminders.slots[0], null);
    expect(t2, 'Going out today?');
    expect(b2, contains('Start your trip'));
  });
}
