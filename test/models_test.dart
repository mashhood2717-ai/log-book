import 'package:flutter_test/flutter_test.dart';
import 'package:trip_logbook/models.dart';
import 'package:trip_logbook/widgets/trip_widgets.dart';

Map<String, dynamic> _row({Map<String, dynamic> extra = const {}}) => {
      'id': 7,
      'driver_id': 'u1',
      'vehicle_id': 3,
      'status': 'completed',
      'start_time': '2026-10-01T04:00:00+00:00',
      'end_time': '2026-10-01T07:30:00+00:00',
      'start_mileage': 1000,
      'end_mileage': 1085,
      'distance_km': 85,
      'purpose': 'Site visit',
      'destination': 'Nowshera',
      'fuel_litres': '20.50', // numeric columns can arrive as strings
      'vehicles': {'reg_no': 'LEB-1234'},
      'profiles': {'full_name': 'Ali'},
      ...extra,
    };

void main() {
  group('Trip.fromMap', () {
    test('parses joins, numbers and duration', () {
      final t = Trip.fromMap(_row());
      expect(t.vehicleRegNo, 'LEB-1234');
      expect(t.driverName, 'Ali');
      expect(t.fuelLitres, 20.5);
      expect(t.duration, const Duration(hours: 3, minutes: 30));
      expect(t.startLocation, isNull);
    });

    test('parses GPS stamps', () {
      final t = Trip.fromMap(_row(extra: {
        'start_lat': 34.0151,
        'start_lng': 71.5249,
        'start_accuracy': 12.0,
        'end_lat': 34.01,
        'end_lng': null, // incomplete point is ignored
      }));
      expect(t.startLocation!.lat, 34.0151);
      expect(t.startLocation!.accuracy, 12.0);
      expect(t.startLocation!.mapsUrl.toString(),
          'https://www.google.com/maps/search/?api=1&query=34.0151,71.5249');
      expect(t.endLocation, isNull);
    });
  });

  test('GeoPoint.toColumns uses the column prefix', () {
    expect(const GeoPoint(1.5, 2.5, accuracy: 9).toColumns('end'),
        {'end_lat': 1.5, 'end_lng': 2.5, 'end_accuracy': 9.0});
  });

  test('durationText', () {
    expect(durationText(const Duration(minutes: 45)), '45m');
    expect(durationText(const Duration(hours: 3, minutes: 20)), '3h 20m');
    expect(durationText(const Duration(days: 2, hours: 4)), '2d 4h');
    expect(durationText(const Duration(minutes: -5)), '0m');
  });

  test('odometerValidator', () {
    expect(odometerValidator(''), isNotNull);
    expect(odometerValidator('123456'), isNull);
    expect(odometerValidator('99999999999'), isNotNull);
  });
}
