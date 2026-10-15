import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models.dart';
import 'route_math.dart';

enum TrackingState { off, starting, on, noPermission, locationOff, failed }

/// The database refused these points (wrong key / trip closed) – drop them.
class PointsRejected implements Exception {}

/// Records the driver's route while a trip is open (a point every 10 s
/// while moving, every 2 min while parked) and uploads it right away with the
/// trip's tracking key.
///
/// * Android: a separate foreground service ("Trip in progress"
///   notification) that keeps running with the screen off and even if the
///   app is swiped away.
/// * iPhone: background location updates (blue indicator) while the app is
///   in memory.
/// Points taken without signal are kept on the phone and uploaded later.
class LocationTracker {
  /// A new point at most every [interval] while the vehicle moves…
  static const interval = Duration(seconds: 10);

  /// …"moving" meaning at least this many metres since the last point…
  static const minMove = 20.0;

  /// …and while parked one point per [heartbeat], so "last seen" stays fresh.
  static const heartbeat = Duration(minutes: 2);
  static const _queueKey = 'pending_trip_points';
  static const _keysKey = 'trip_tracking_keys';
  static const _maxQueue = 20000; // ~2 days offline at 1 point / 10 s

  static final state = ValueNotifier<TrackingState>(TrackingState.off);
  static int? _tripId;
  static StreamSubscription<Position>? _sub; // iPhone
  static TrackPoint? _lastPoint;
  static final List<TrackPoint> _queue = [];
  static final Map<int, String> _keys = {}; // trip id -> tracking key
  static bool _loaded = false;
  static bool _flushing = false;

  /// Replaceable for tests; normally calls the add_trip_points function.
  @visibleForTesting
  static Future<void> Function(int tripId, String key, List<Map<String, dynamic>> rows)
      upload = _rpcUpload;

  static int? get activeTripId => _tripId;
  static int get pendingCount => _queue.length;

  /// Call once in main(): lets the Android service report back to the app.
  static void initMain() {
    if (!Platform.isAndroid) return;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.addTaskDataCallback((data) {
      if (data is String) {
        state.value = TrackingState.values.firstWhere((s) => s.name == data,
            orElse: () => state.value);
      }
    });
  }

  /// Start (or keep) recording [tripId]. Safe to call repeatedly.
  static Future<void> start(int tripId, String key) async {
    if (_tripId == tripId &&
        (state.value == TrackingState.on || state.value == TrackingState.starting)) {
      return;
    }
    _tripId = tripId;
    state.value = TrackingState.starting;
    await _load();
    _keys[tripId] = key;
    await _save();
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        state.value = TrackingState.locationOff;
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        state.value = TrackingState.noPermission;
        return;
      }
      if (Platform.isAndroid) {
        await _startAndroidService(tripId, key);
      } else {
        await _startStream();
      }
      state.value = TrackingState.on;
      unawaited(flush());
    } catch (e) {
      debugPrint('Could not start tracking: $e');
      state.value = TrackingState.failed;
    }
  }

  /// Stop recording (trip ended / signed out) and upload what's left.
  static Future<void> stop() async {
    _tripId = null;
    _lastPoint = null;
    await _sub?.cancel();
    _sub = null;
    if (Platform.isAndroid && await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService(); // the service uploads on exit
    }
    state.value = TrackingState.off;
    await flush();
  }

  // ---------------- Android: foreground service ----------------
  static Future<void> _startAndroidService(int tripId, String key) async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'trip_tracking',
        channelName: 'Trip tracking',
        channelDescription: 'Shown while your route is being recorded',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(60 * 1000),
        allowWakeLock: true,
        allowWifiLock: true,
        stopWithTask: false, // keep going if the app is swiped away
      ),
    );
    if (await FlutterForegroundTask.isRunningService) {
      final running = await FlutterForegroundTask.getData<int>(key: 'trip_id');
      if (running == tripId) return;
      await FlutterForegroundTask.stopService();
    }
    await FlutterForegroundTask.saveData(key: 'trip_id', value: tripId);
    await FlutterForegroundTask.saveData(key: 'trip_key', value: key);
    final r = await FlutterForegroundTask.startService(
      serviceId: 501,
      serviceTypes: [ForegroundServiceTypes.location],
      notificationTitle: 'Trip in progress',
      notificationText: 'Trip Logbook is recording your route',
      notificationIcon: const NotificationIcon(
          metaDataName: 'com.weatherwalay.trip_logbook.TRACKING_ICON'),
      callback: trackingServiceEntry,
    );
    if (r is ServiceRequestFailure) throw r.error;
  }

  /// Runs inside the Android service (its own Dart isolate).
  static Future<void> serviceStarted(int tripId, String key) async {
    _tripId = tripId;
    await _load();
    _keys[tripId] = key;
    await _save();
  }

  // ---------------- iPhone: background location stream ----------------
  static Future<void> _startStream() async {
    await _sub?.cancel();
    _sub = Geolocator.getPositionStream(
      locationSettings: AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: 0, // every fix; addPoint keeps 1 per 10 s / 2 min
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      ),
    ).listen((p) => addPosition(p), onError: (Object e) {
      state.value = e is LocationServiceDisabledException
          ? TrackingState.locationOff
          : TrackingState.failed;
    });
  }

  // ---------------- Queue & upload (both platforms) ----------------
  static Future<void> addPosition(Position p) => addPoint(TrackPoint(
        tripId: _tripId ?? -1,
        recordedAt: p.timestamp,
        lat: p.latitude,
        lng: p.longitude,
        accuracy: p.accuracy,
        speed: p.speed >= 0 ? p.speed : null,
      ));

  /// Queue a point and upload it. Keeps at most one per [interval], and
  /// while parked (moved < [minMove] m) only one per [heartbeat].
  @visibleForTesting
  static Future<void> addPoint(TrackPoint p) async {
    if (p.tripId < 0) return;
    final last = _lastPoint;
    if (last != null && last.tripId == p.tripId) {
      final dt = p.recordedAt.difference(last.recordedAt);
      if (dt < interval) return;
      final moved = kmBetween(last.lat, last.lng, p.lat, p.lng) * 1000;
      if (moved < minMove && dt < heartbeat) return;
    }
    _lastPoint = p;
    await _load();
    _queue.add(p);
    if (_queue.length > _maxQueue) {
      _queue.removeRange(0, _queue.length - _maxQueue);
    }
    await _save();
    await flush();
  }

  /// Upload queued points in batches, per trip.
  static Future<void> flush() async {
    if (_flushing || _queue.isEmpty) return;
    _flushing = true;
    try {
      while (_queue.isNotEmpty) {
        final tripId = _queue.first.tripId;
        final batch = _queue.takeWhile((p) => p.tripId == tripId).take(200).toList();
        final key = _keys[tripId];
        try {
          if (key == null) throw PointsRejected(); // can never be sent
          await upload(tripId, key, batch.map((p) => p.toMap()).toList());
          _queue.removeRange(0, batch.length);
        } on PointsRejected {
          _queue.removeRange(0, batch.length);
        } catch (_) {
          break; // offline – try again with the next point / app resume
        }
      }
      // Forget keys of trips that have nothing left to send.
      final needed = {..._queue.map((p) => p.tripId), if (_tripId != null) _tripId!};
      _keys.removeWhere((id, _) => !needed.contains(id));
      await _save();
    } finally {
      _flushing = false;
    }
  }

  static Future<void> _rpcUpload(
      int tripId, String key, List<Map<String, dynamic>> rows) async {
    final res = await http
        .post(
          Uri.parse('${AppConfig.supabaseUrl}/rest/v1/rpc/add_trip_points'),
          headers: {
            'apikey': AppConfig.supabaseKey,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'p_trip_id': tripId, 'p_key': key, 'p_points': rows}),
        )
        .timeout(const Duration(seconds: 20));
    // Visible with `adb logcat` – handy when checking a driver's phone.
    debugPrint('TRACK_UPLOAD trip $tripId: ${rows.length} point(s) -> HTTP ${res.statusCode}');
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    if (res.statusCode == 401 || res.statusCode == 403 || res.body.contains('42501')) {
      throw PointsRejected();
    }
    throw Exception('Upload failed (${res.statusCode})');
  }

  static Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload(); // the Android service may have written meanwhile
      final q = prefs.getString(_queueKey);
      if (q != null) {
        _queue.addAll((jsonDecode(q) as List)
            .cast<Map<String, dynamic>>()
            .map(TrackPoint.fromMap));
      }
      final k = prefs.getString(_keysKey);
      if (k != null) {
        _keys.addAll((jsonDecode(k) as Map<String, dynamic>)
            .map((id, key) => MapEntry(int.parse(id), key as String)));
      }
    } catch (_) {}
  }

  static Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _queueKey, jsonEncode(_queue.map((p) => p.toMap()).toList()));
      await prefs.setString(
          _keysKey, jsonEncode(_keys.map((id, key) => MapEntry('$id', key))));
    } catch (_) {}
  }

  @visibleForTesting
  static void resetForTest({int? tripId, String key = 'k'}) {
    _queue.clear();
    _keys.clear();
    _loaded = true;
    _lastPoint = null;
    _flushing = false;
    _tripId = tripId;
    if (tripId != null) _keys[tripId] = key;
  }
}

// ---------------- The Android service's own entry point ----------------
@pragma('vm:entry-point')
void trackingServiceEntry() =>
    FlutterForegroundTask.setTaskHandler(_TrackingTask());

class _TrackingTask extends TaskHandler {
  StreamSubscription<Position>? _sub;
  bool _warned = false; // notification currently says location is off

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final id = await FlutterForegroundTask.getData<int>(key: 'trip_id');
    final key = await FlutterForegroundTask.getData<String>(key: 'trip_key');
    if (id == null || key == null) return;
    await LocationTracker.serviceStarted(id, key);
    _listen();
  }

  /// GPS fixes every [LocationTracker.interval]; addPoint thins them out.
  void _listen() {
    _sub?.cancel();
    _sub = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: LocationTracker.interval,
      ),
    ).listen((p) {
      LocationTracker.addPosition(p);
      FlutterForegroundTask.sendDataToMain(TrackingState.on.name);
      if (_warned) {
        _warned = false;
        FlutterForegroundTask.updateService(
            notificationText: 'Trip Logbook is recording your route');
      }
    }, onError: (Object e) {
      debugPrint('Tracking stream error: $e');
      _sub = null; // the watchdog below restarts it
      if (e is LocationServiceDisabledException) {
        FlutterForegroundTask.sendDataToMain(TrackingState.locationOff.name);
        _warned = true;
        FlutterForegroundTask.updateService(
            notificationText: 'Location is off – your route is not being recorded');
      }
    });
  }

  /// Every minute: restart the stream if it stopped, retry waiting uploads.
  @override
  void onRepeatEvent(DateTime timestamp) {
    if (_sub == null) _listen();
    LocationTracker.flush();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _sub?.cancel();
    await LocationTracker.flush();
  }
}
