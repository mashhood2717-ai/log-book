import 'dart:math' as math;

import '../models.dart';

/// Distance between two GPS points in kilometres (haversine formula).
double kmBetween(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0; // Earth radius, km
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1), dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}

/// Length of a route in km. Fixes worse than [maxAccuracyM] are skipped so a
/// single bad GPS jump doesn't add kilometres.
double routeKm(List<TrackPoint> pts, {double maxAccuracyM = 100}) {
  final good =
      pts.where((p) => p.accuracy == null || p.accuracy! <= maxAccuracyM).toList();
  var km = 0.0;
  for (var i = 1; i < good.length; i++) {
    km += kmBetween(good[i - 1].lat, good[i - 1].lng, good[i].lat, good[i].lng);
  }
  return km;
}

/// A stretch with no location (phone off, no signal, app stopped…).
class RouteGap {
  final DateTime from, to;
  const RouteGap(this.from, this.to);
  Duration get length => to.difference(from);
}

/// Gaps longer than [threshold] between consecutive points, plus the time
/// from the trip start to the first point and from the last point to the end
/// (or to [now] for an open trip).
List<RouteGap> routeGaps(List<TrackPoint> pts,
    {required DateTime start,
    DateTime? end,
    DateTime? now,
    Duration threshold = const Duration(minutes: 10)}) {
  final times = [start, ...pts.map((p) => p.recordedAt), end ?? now ?? DateTime.now()];
  final gaps = <RouteGap>[];
  for (var i = 1; i < times.length; i++) {
    if (times[i].difference(times[i - 1]) > threshold) {
      gaps.add(RouteGap(times[i - 1], times[i]));
    }
  }
  return gaps;
}

/// True when the GPS route and the odometer disagree enough to look at:
/// more than [ratio] apart and more than [minKm] in absolute terms.
bool distanceMismatch(double gpsKm, int? odometerKm,
    {double ratio = 0.15, double minKm = 3}) {
  if (odometerKm == null || odometerKm <= 0 || gpsKm <= 0) return false;
  final diff = (gpsKm - odometerKm).abs();
  return diff > minKm && diff / odometerKm > ratio;
}
