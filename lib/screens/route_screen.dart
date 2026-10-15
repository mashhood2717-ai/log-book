import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import '../models.dart';
import '../services/db.dart';
import '../services/route_math.dart';
import '../widgets/brand.dart';
import '../widgets/trip_map.dart';
import '../widgets/trip_widgets.dart';

/// A trip's recorded route on a map. While the trip is open new points
/// arrive live (Supabase Realtime), with a 15 s top-up as fallback.
class RouteScreen extends StatefulWidget {
  final Trip trip;
  const RouteScreen({super.key, required this.trip});

  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> {
  List<TrackPoint>? _points;
  Object? _error;
  Timer? _timer;
  RealtimeChannel? _live;
  final _map = MapController();

  Trip get t => widget.trip;

  @override
  void initState() {
    super.initState();
    _load();
    if (t.isOngoing) {
      _timer = Timer.periodic(const Duration(seconds: 15), (_) => _topUp());
      _live = Db.watchTripPoints(_add, tripId: t.id);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_live != null) Db.unwatch(_live!);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final pts = await Db.tripPoints(t.id);
      if (!mounted) return;
      setState(() {
        _points = pts;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Fetch only points newer than the last one we have.
  Future<void> _topUp() async {
    final have = _points;
    if (have == null) return _load();
    try {
      final more = await Db.tripPoints(t.id,
          after: have.isEmpty ? null : have.last.recordedAt);
      more.forEach(_add);
    } catch (_) {} // keep showing what we have
  }

  void _add(TrackPoint p) {
    final have = _points;
    if (!mounted || have == null) return;
    if (have.isNotEmpty && !p.recordedAt.isAfter(have.last.recordedAt)) return;
    setState(() => _points = [...have, p]);
  }

  List<LatLng> _line(List<TrackPoint> pts) => [
        if (t.startLocation != null)
          LatLng(t.startLocation!.lat, t.startLocation!.lng),
        ...pts.map((p) => LatLng(p.lat, p.lng)),
        if (!t.isOngoing && t.endLocation != null)
          LatLng(t.endLocation!.lat, t.endLocation!.lng),
      ];

  @override
  Widget build(BuildContext context) {
    final pts = _points;
    return Scaffold(
      appBar: AppBar(
        title: Text('${t.vehicleRegNo} → ${t.destination}'),
        actions: [
          if (pts != null && pts.isNotEmpty)
            IconButton(
              tooltip: 'Show whole route',
              icon: const Icon(Icons.fit_screen_outlined),
              onPressed: () => _map.fitCamera(CameraFit.coordinates(
                  coordinates: _line(pts),
                  padding: const EdgeInsets.all(56),
                  maxZoom: 16)),
            ),
        ],
      ),
      body: pts == null
          ? Center(
              child: _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(Db.friendlyError(_error!),
                          textAlign: TextAlign.center))
                  : const BrandLoader(label: 'Loading route…'))
          : Column(children: [
              Expanded(child: _mapView(pts)),
              _summary(pts),
            ]),
    );
  }

  Widget _mapView(List<TrackPoint> pts) {
    final line = _line(pts);
    final start = line.isEmpty ? null : line.first;
    final end = line.length < 2 ? null : line.last;
    return FlutterMap(
      mapController: _map,
      // Fits the route once; after that the admin moves the map freely.
      options: fitOptions(line),
      children: [
        ...baseMapLayers(context),
        if (line.length >= 2)
          PolylineLayer(polylines: [
            Polyline(
              points: line,
              strokeWidth: 5,
              color: Brand.blue,
              borderStrokeWidth: 2,
              borderColor: Colors.white,
            ),
          ]),
        MarkerLayer(markers: [
          if (start != null)
            Marker(
              point: start,
              width: 40,
              height: 40,
              child: const MapPin(icon: Icons.play_arrow, color: Colors.green),
            ),
          if (end != null)
            Marker(
              point: end,
              width: 110,
              height: 62,
              alignment: Alignment.topCenter,
              child: t.isOngoing
                  ? MapPin(
                      icon: Icons.directions_car,
                      color: Brand.orange,
                      label: t.vehicleRegNo)
                  : const MapPin(icon: Icons.flag, color: Colors.red),
            ),
        ]),
      ],
    );
  }

  Widget _summary(List<TrackPoint> pts) {
    final c = context.colors;
    final gpsKm = routeKm(pts);
    final gaps = routeGaps(pts,
        start: t.startTime, end: t.endTime, now: DateTime.now());
    final mismatch = distanceMismatch(gpsKm, t.distanceKm);
    final last = pts.isEmpty ? null : pts.last;
    Widget stat(String label, String value, {Color? color}) => Expanded(
          child: Column(children: [
            Text(value,
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: color ?? c.accent)),
            Text(label, style: TextStyle(fontSize: 12, color: c.muted)),
          ]),
        );

    return Material(
      color: c.card,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${t.driverName} · ${t.purpose}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
            if (t.isOngoing)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                    last == null
                        ? 'No location received yet'
                        : 'Last seen ${agoText(last.recordedAt)} (${timeFmt.format(last.recordedAt)}) · live',
                    style: TextStyle(fontSize: 12, color: c.muted)),
              ),
            const SizedBox(height: 10),
            Row(children: [
              stat('GPS distance', '${gpsKm.toStringAsFixed(1)} km'),
              stat('Odometer', km(t.distanceKm),
                  color: mismatch ? c.amberText : null),
              stat('Points', '${pts.length}'),
            ]),
            if (pts.isEmpty)
              _note(Icons.location_off,
                  'No route recorded for this trip. The driver may have an older app version or location switched off.'),
            if (mismatch)
              _note(Icons.warning_amber_rounded,
                  'GPS distance and odometer differ by ${(gpsKm - t.distanceKm!).abs().toStringAsFixed(0)} km – worth checking.'),
            if (pts.isNotEmpty && gaps.isNotEmpty)
              _note(
                  Icons.signal_cellular_connected_no_internet_4_bar,
                  'No location for ${gaps.length == 1 ? '' : '${gaps.length} periods, '}'
                  '${gaps.map((g) => '${timeFmt.format(g.from)}–${timeFmt.format(g.to)}').take(3).join(', ')}'
                  '${gaps.length > 3 ? '…' : ''}'),
          ]),
        ),
      ),
    );
  }

  Widget _note(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: context.colors.amberText),
          const SizedBox(width: 6),
          Expanded(
              child: Text(text,
                  style: TextStyle(fontSize: 13, color: context.colors.ink))),
        ]),
      );
}
