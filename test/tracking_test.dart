import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trip_logbook/models.dart';
import 'package:trip_logbook/services/location_tracker.dart';
import 'package:trip_logbook/services/route_math.dart';
import 'package:trip_logbook/widgets/trip_map.dart';

TrackPoint pt(int sec, double lat, double lng, {double? acc}) => TrackPoint(
    tripId: 7,
    recordedAt: DateTime.utc(2026, 10, 14, 5).add(Duration(seconds: sec)),
    lat: lat,
    lng: lng,
    accuracy: acc);

void main() {
  group('route maths', () {
    test('Peshawar → Nowshera is about 41 km in a straight line', () {
      expect(kmBetween(34.0151, 71.5249, 34.0153, 71.9747), closeTo(41.5, 0.5));
    });

    test('route length adds the legs and skips inaccurate fixes', () {
      final route = [
        pt(0, 34.0, 71.5),
        pt(60, 34.01, 71.5), // ~1.11 km north
        pt(120, 35.0, 72.0, acc: 900), // bad jump – ignored
        pt(180, 34.02, 71.5), // another ~1.11 km
      ];
      expect(routeKm(route), closeTo(2.22, 0.02));
    });

    test('gaps: before the first point, between points, after the last', () {
      final start = DateTime.utc(2026, 10, 14, 4, 45); // 15 min before 1st point
      final gaps = routeGaps([pt(0, 0, 0), pt(60, 0, 0), pt(1260, 0, 0)],
          start: start, end: DateTime.utc(2026, 10, 14, 5, 22));
      expect(gaps.length, 2); // 15 min at start, 20 min in the middle
      expect(gaps[0].length.inMinutes, 15);
      expect(gaps[1].length.inMinutes, 20);
    });

    test('mismatch only when clearly different', () {
      expect(distanceMismatch(88, 90), isFalse); // 2 km off
      expect(distanceMismatch(60, 90), isTrue); // 30 km off
      expect(distanceMismatch(4, 2), isFalse); // tiny trip
      expect(distanceMismatch(50, null), isFalse);
    });

    test('ago text', () {
      final now = DateTime(2026, 10, 14, 12);
      expect(agoText(now.subtract(const Duration(seconds: 20)), now: now), 'just now');
      expect(agoText(now.subtract(const Duration(minutes: 4)), now: now), '4 min ago');
      expect(agoText(now.subtract(const Duration(hours: 2)), now: now), '2 h ago');
    });
  });

  group('tracker queue', () {
    late List<List<Map<String, dynamic>>> uploads;
    Object? failWith;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      LocationTracker.resetForTest(tripId: 7, key: 'secret');
      uploads = [];
      failWith = null;
      LocationTracker.upload = (tripId, key, rows) async {
        expect(key, 'secret');
        if (failWith != null) throw failWith!;
        uploads.add(rows);
      };
    });

    test('every 10 s while moving', () async {
      // ~110 m north every 10 s
      for (var i = 0; i < 6; i++) {
        await LocationTracker.addPoint(pt(i * 10, 34 + i * 0.001, 71));
      }
      await LocationTracker.addPoint(pt(55, 34.0059, 71)); // only 5 s later
      expect(uploads.expand((b) => b).length, 6);
    });

    test('parked: one point every 2 minutes', () async {
      // Standing still (a few metres of GPS wobble), a fix every 10 s for 5 min
      for (var s = 0; s <= 300; s += 10) {
        await LocationTracker.addPoint(pt(s, 34 + (s % 20) * 0.000005, 71));
      }
      // 0 s, 120 s, 240 s
      expect(uploads.expand((b) => b).length, 3);
    });

    test('offline points are kept and sent together later', () async {
      failWith = Exception('no internet');
      await LocationTracker.addPoint(pt(0, 34, 71));
      await LocationTracker.addPoint(pt(10, 34.001, 71));
      expect(LocationTracker.pendingCount, 2);
      failWith = null;
      await LocationTracker.flush();
      expect(LocationTracker.pendingCount, 0);
      expect(uploads.single.length, 2);
      expect(uploads.single.first['trip_id'], 7);
    });

    test('points the database refuses are dropped, not retried forever', () async {
      failWith = PointsRejected();
      await LocationTracker.addPoint(pt(0, 34, 71));
      expect(LocationTracker.pendingCount, 0);
    });
  });
}
