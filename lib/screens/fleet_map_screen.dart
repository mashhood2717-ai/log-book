import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models.dart';
import '../services/db.dart';
import '../widgets/brand.dart';
import '../widgets/trip_map.dart';
import '../widgets/trip_widgets.dart';
import 'route_screen.dart';

/// Admin: where every vehicle that's out is right now. Refreshes every 30 s.
class FleetMapScreen extends StatefulWidget {
  const FleetMapScreen({super.key});

  @override
  State<FleetMapScreen> createState() => _FleetMapScreenState();
}

class _FleetMapScreenState extends State<FleetMapScreen> {
  List<Trip>? _trips;
  Map<int, TrackPoint> _pos = {};
  Object? _error;
  DateTime? _loadedAt;
  Timer? _timer;
  final _map = MapController();

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final trips = await Db.openTrips();
      final pos = await Db.lastPositions(trips.map((t) => t.id).toList());
      if (!mounted) return;
      setState(() {
        _trips = trips;
        _pos = pos;
        _error = null;
        _loadedAt = DateTime.now();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Latest point, or the start GPS if no route point arrived yet.
  LatLng? _where(Trip t) {
    final p = _pos[t.id];
    if (p != null) return LatLng(p.lat, p.lng);
    final s = t.startLocation;
    return s == null ? null : LatLng(s.lat, s.lng);
  }

  /// When the phone last sent a live point (null = only the start is known).
  DateTime? _seen(Trip t) => _pos[t.id]?.recordedAt;

  /// True when the pin is only the trip's starting point, not a live position
  /// (driver on an old app version, or location off since starting).
  bool _startOnly(Trip t) => _pos[t.id] == null;

  @override
  Widget build(BuildContext context) {
    final trips = _trips;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live map'),
        actions: [
          IconButton(
              tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: trips == null
          ? Center(
              child: _error != null
                  ? Text(Db.friendlyError(_error!))
                  : const BrandLoader(label: 'Finding vehicles…'))
          : Column(children: [
              Expanded(child: _mapView(trips)),
              _footer(trips),
            ]),
    );
  }

  Widget _mapView(List<Trip> trips) {
    final located = [for (final t in trips) if (_where(t) != null) t];
    return FlutterMap(
      mapController: _map,
      options: fitOptions(located.map((t) => _where(t)!).toList(), maxZoom: 14),
      children: [
        ...baseMapLayers(context),
        MarkerLayer(markers: [
          for (final t in located)
            Marker(
              point: _where(t)!,
              width: 120,
              height: 62,
              alignment: Alignment.topCenter,
              child: GestureDetector(
                onTap: () => _showTrip(t),
                child: MapPin(
                  // Flag + "start" when there is no live position yet.
                  icon: _startOnly(t) ? Icons.flag_outlined : Icons.directions_car,
                  // Grey when we haven't heard from the phone for 15+ minutes.
                  color: _stale(t) ? Colors.grey : Brand.orange,
                  label: _startOnly(t)
                      ? '${t.vehicleRegNo} · start'
                      : t.vehicleRegNo,
                ),
              ),
            ),
        ]),
      ],
    );
  }

  bool _stale(Trip t) {
    final seen = _seen(t);
    return seen == null ||
        DateTime.now().difference(seen) > const Duration(minutes: 15);
  }

  Widget _footer(List<Trip> trips) {
    final c = context.colors;
    final missing = trips.where(_startOnly).toList();
    return Material(
      color: c.card,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                trips.isEmpty
                    ? 'No vehicles are out right now.'
                    : '${trips.length} vehicle${trips.length == 1 ? '' : 's'} out · tap a car for details',
                style: TextStyle(fontWeight: FontWeight.w700, color: c.ink),
              ),
              if (missing.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'No live location (pin = where the trip started): '
                    '${missing.map((t) => '${t.vehicleRegNo} (${t.driverName})').join(', ')}. '
                    'The driver needs app v1.7.0+ with location on.',
                    style: TextStyle(fontSize: 12, color: c.amberText),
                  ),
                ),
              if (_loadedAt != null)
                Text('Updated ${timeFmt.format(_loadedAt!)} · 🚗 live · 🏁 start only · grey = silent 15+ min',
                    style: TextStyle(fontSize: 12, color: c.muted)),
            ],
          ),
        ),
      ),
    );
  }

  void _showTrip(Trip t) {
    final seen = _seen(t);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${t.vehicleRegNo} → ${t.destination}',
                  style: Theme.of(c).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text('${t.driverName} · ${t.purpose}'),
              Text('Left ${dateTimeFmt.format(t.startTime)} · out for ${durationText(t.duration)}'),
              Text(seen == null
                  ? 'No live location – the pin shows where the trip started '
                      '(${timeFmt.format(t.startTime)}). The driver needs app '
                      'version 1.7.0 or newer with location switched on.'
                  : 'Last seen ${agoText(seen)}'),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(c);
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => RouteScreen(trip: t)));
                },
                icon: const Icon(Icons.route),
                label: const Text('View route'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
