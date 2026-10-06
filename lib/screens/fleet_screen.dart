import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../services/db.dart';
import '../widgets/animations.dart';
import '../widgets/brand.dart';
import '../widgets/trip_widgets.dart';

class _FleetData {
  final List<(Vehicle, Trip)> out;
  final List<Vehicle> available;
  final DateTime loadedAt;
  _FleetData(this.out, this.available) : loadedAt = DateTime.now();
}

/// Admin: which vehicles are out right now, with whom, where to and since when.
class FleetScreen extends StatefulWidget {
  const FleetScreen({super.key});

  @override
  State<FleetScreen> createState() => _FleetScreenState();
}

class _FleetScreenState extends State<FleetScreen> {
  _FleetData? _data; // last good load – kept if a refresh fails
  Object? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Keep the board fresh while it's on screen.
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<_FleetData> _load() async {
    final results = await Future.wait([Db.vehicles(), Db.openTrips()]);
    final vehicles = results[0] as List<Vehicle>;
    final trips = {for (final t in results[1] as List<Trip>) t.vehicleId: t};
    final out = <(Vehicle, Trip)>[];
    final available = <Vehicle>[];
    for (final v in vehicles) {
      final t = trips[v.id];
      if (t != null) {
        out.add((v, t));
      } else if (v.active) {
        available.add(v);
      }
    }
    // Longest-out first – those are the ones to ask about.
    out.sort((a, b) => a.$2.startTime.compareTo(b.$2.startTime));
    return _FleetData(out, available);
  }

  Future<void> _refresh() async {
    try {
      final d = await _load();
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fleet status'),
        actions: [
          IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: _refresh),
        ],
      ),
      body: RefreshIndicator(onRefresh: _refresh, child: _body()),
    );
  }

  Widget _body() {
    final d = _data;
    if (d == null && _error != null) {
      return ListView(children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(Db.friendlyError(_error!), textAlign: TextAlign.center),
        ),
      ]);
    }
    if (d == null) return const BrandLoaderList(label: 'Checking the fleet…');

    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(children: [
            _count('Out now', d.out.length, Brand.sunGradient, Icons.route),
            const SizedBox(width: 12),
            _count('Available', d.available.length, Brand.blueGradient,
                Icons.local_parking),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            'Updated ${DateFormat('hh:mm a').format(d.loadedAt)}'
            '${_error != null ? ' · refresh failed, showing last data' : ''}',
            style: theme.textTheme.bodySmall,
          ),
        ),
        _header('Out now'),
        if (d.out.isEmpty) _empty('All vehicles are in.'),
        for (final (i, e) in d.out.indexed)
          FadeSlideIn(index: i + 1, child: _outCard(e.$1, e.$2)),
        _header('Available'),
        if (d.available.isEmpty) _empty('No vehicles available.'),
        for (final (i, v) in d.available.indexed)
          FadeSlideIn(index: d.out.length + i + 2, child: _availableTile(v)),
      ],
    );
  }

  Widget _count(String label, int n, Gradient gradient, IconData icon) =>
      Expanded(
        child: FadeSlideIn(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: gradient.colors.last.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 8)),
              ],
            ),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CountUp(
                      value: n,
                      format: (v) => '$v',
                      style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1),
                    ),
                    const SizedBox(height: 4),
                    Text(label,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Icon(icon, color: Colors.white.withValues(alpha: 0.7), size: 30),
            ]),
          ),
        ),
      );

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700, color: Brand.ink)),
      );

  Widget _empty(String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(text, style: TextStyle(color: Colors.grey.shade600)),
      );

  Widget _outCard(Vehicle v, Trip t) {
    final muted = TextStyle(color: Brand.ink.withValues(alpha: 0.6));
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          if (await showTripDetails(context, t)) _refresh();
        },
        child: Container(
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: Brand.orange, width: 5)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 14, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const PulsingDot(color: Brand.orange, size: 9),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(v.label,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Brand.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Brand.orange.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(durationText(t.duration),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFB36B00))),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Icon(Icons.person, size: 18, color: Brand.blue),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(t.driverName,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward, size: 16),
                ),
                Icon(Icons.place, size: 18, color: Brand.orange),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(t.destination,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ]),
              const SizedBox(height: 4),
              Text(t.purpose, style: muted),
              const SizedBox(height: 4),
              Text('Left ${dateTimeFmt.format(t.startTime)} · at ${km(t.startMileage)}',
                  style: muted),
              const SizedBox(height: 4),
              LocationLink(t.startLocation),
            ],
          ),
        ),
      ),
    );
  }

  Widget _availableTile(Vehicle v) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        child: ListTile(
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Brand.blue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.local_parking, color: Brand.blue),
          ),
          title: Text(v.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: Brand.ink)),
          subtitle: Text('Odometer: ${km(v.lastOdometer)}'),
        ),
      );
}
