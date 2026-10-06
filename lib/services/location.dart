import 'package:geolocator/geolocator.dart';

import '../models.dart';

/// Result of trying to read the phone's GPS.
class LocationResult {
  final GeoPoint? point;

  /// Why there is no point, in words a driver understands.
  final String? problem;

  const LocationResult.ok(GeoPoint this.point) : problem = null;
  const LocationResult.failed(this.problem) : point = null;
}

/// Reads the phone's own GPS (no Google API key involved).
/// Never throws – a trip must not be blocked because GPS is unavailable.
class LocationService {
  static Future<LocationResult> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationResult.failed('Location is turned off on this phone.');
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return const LocationResult.failed(
            'Location permission was not given to the app.');
      }

      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 20),
          ),
        );
      } catch (_) {
        // No fix in time (e.g. indoors) – use the last known position if recent.
        final last = await Geolocator.getLastKnownPosition();
        if (last != null &&
            DateTime.now().difference(last.timestamp) <
                const Duration(minutes: 10)) {
          pos = last;
        }
      }
      if (pos == null) {
        return const LocationResult.failed('Could not get a GPS fix.');
      }
      return LocationResult.ok(
          GeoPoint(pos.latitude, pos.longitude, accuracy: pos.accuracy));
    } catch (_) {
      return const LocationResult.failed('Could not read location.');
    }
  }

  /// Opens the phone's settings so the driver can allow location.
  static Future<void> openSettings() async {
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
    } else {
      await Geolocator.openLocationSettings();
    }
  }
}
