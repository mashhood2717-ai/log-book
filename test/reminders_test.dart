import 'package:flutter_test/flutter_test.dart';
import 'package:trip_logbook/models.dart';
import 'package:trip_logbook/services/reminders.dart';

void main() {
  // Pakistan is UTC+5 all year (no daylight saving).
  // 2026-10-14 is a Wednesday.
  DateTime utc(int day, int h, int m) => DateTime.utc(2026, 10, day, h, m);
  const mon = DateTime.monday, wed = DateTime.wednesday;
  const sat = DateTime.saturday, sun = DateTime.sunday;

  group('schedule', () {
    final slots = Reminders.slots;
    List<int> hoursOn(int day) =>
        slots.where((s) => s.weekday == day).map((s) => s.hour).toList();

    test('Mon–Fri every hour 9 AM to 6 PM', () {
      for (var d = mon; d <= DateTime.friday; d++) {
        expect(hoursOn(d), [9, 10, 11, 12, 13, 14, 15, 16, 17, 18]);
      }
    });

    test('weekends 11 AM and 5 PM', () {
      expect(hoursOn(sat), [11, 17]);
      expect(hoursOn(sun), [11, 17]);
    });

    test('54 reminders with unique ids (iPhone allows 64)', () {
      expect(slots.length, 54);
      expect(slots.map((s) => s.id).toSet().length, 54);
      expect(slots.length, lessThan(64));
    });

    test('last of the day is 6 PM weekdays, 5 PM weekends', () {
      final last = slots.where((s) => s.lastOfDay);
      expect(last.where((s) => s.weekday <= 5).map((s) => s.hour).toSet(), {18});
      expect(last.where((s) => s.weekday >= 6).map((s) => s.hour).toSet(), {17});
    });

    test('settings text', () {
      expect(Reminders.scheduleText,
          'Mon–Fri every hour, 9 AM–6 PM · Sat–Sun 11 AM & 5 PM (Pakistan time)');
    });
  });

  group('next time, in Pakistan time', () {
    test('later the same day', () {
      // Wed 08:00 PKT -> Wed 09:00 PKT (= 04:00 UTC)
      final t = Reminders.nextPkt(wed, 9, now: utc(14, 3, 0));
      expect(t.location.name, 'Asia/Karachi');
      expect(t.toUtc(), utc(14, 4, 0));
    });

    test('same weekday, hour already passed -> next week', () {
      // Wed 10:00 PKT, asking for Wed 9 AM -> Wed 21 Oct
      final t = Reminders.nextPkt(wed, 9, now: utc(14, 5, 0));
      expect([t.day, t.weekday, t.hour], [21, wed, 9]);
    });

    test('weekend slot from a weekday', () {
      // Wed -> Sat 17 Oct 11:00 PKT
      final t = Reminders.nextPkt(sat, 11, now: utc(14, 5, 0));
      expect([t.day, t.weekday, t.hour], [17, sat, 11]);
    });

    test('rejects impossible weekdays instead of looping', () {
      expect(() => Reminders.nextPkt(11, 0), throwsRangeError);
    });
  });

  group('wording', () {
    final trip = Trip.fromMap({
      'id': 1, 'driver_id': 'd', 'vehicle_id': 1, 'status': 'ongoing',
      'start_time': '2026-10-14T05:12:00Z', 'start_mileage': 1,
      'purpose': 'p', 'destination': 'Nowshera',
      'vehicles': {'reg_no': 'LEB-1234'},
    });
    const midday = ReminderSlot(wed, 13), evening = ReminderSlot(wed, 18, lastOfDay: true);

    test('open trip is mentioned', () {
      final (title, body) = Reminders.message(midday, trip);
      expect(title, 'Back yet?');
      expect(body, contains('LEB-1234 → Nowshera is still open'));
    });

    test('no trip: start one before leaving', () {
      expect(Reminders.message(midday, null).$1, 'Going out?');
    });

    test('end of day: check everything is logged', () {
      expect(Reminders.message(evening, null).$1, "Logged today's trips?");
      expect(Reminders.message(evening, trip).$1, 'Trip still open');
    });
  });
}
