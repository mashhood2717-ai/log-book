import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../services/db.dart';
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
    if (d == null) return const Center(child: CircularProgressIndicator());

    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(children: [
            _count('Out now', d.out.length, Colors.orange.shade800),
            const SizedBox(width: 12),
            _count('Available', d.available.length, Colors.green.shade700),
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
        ...d.out.map((e) => _outCard(e.$1, e.$2)),
        _header('Available'),
        if (d.available.isEmpty) _empty('No vehicles available.'),
        ...d.available.map(_availableTile),
      ],
    );
  }

  Widget _count(String label, int n, Color color) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(children: [
              Text('$n',
                  style: TextStyle(
                      fontSize: 28, fontWeight: FontWeight.bold, color: color)),
              Text(label),
            ]),
          ),
        ),
      );

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _empty(String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(text, style: TextStyle(color: Colors.grey.shade600)),
      );

  Widget _outCard(Vehicle v, Trip t) {
    final theme = Theme.of(context);
    final muted = TextStyle(color: Colors.grey.shade700);
    return Card(
      color: Colors.orange.shade50,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: InkWell(
        onTap: () => showTripDetails(context, t),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.directions_car, color: Colors.orange.shade800),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(v.label,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                Text(durationText(t.duration),
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade900)),
              ]),
              const SizedBox(height: 8),
              Text('${t.driverName}  →  ${t.destination}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(t.purpose, style: muted),
              const SizedBox(height: 4),
              Text('Left ${dateTimeFmt.format(t.startTime)}'
                  ' · at ${km(t.startMileage)}', style: muted),
              const SizedBox(height: 2),
              LocationLink(t.startLocation),
            ],
          ),
        ),
      ),
    );
  }

  Widget _availableTile(Vehicle v) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: ListTile(
          leading: Icon(Icons.local_parking, color: Colors.green.shade700),
          title: Text(v.label, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('Odometer: ${km(v.lastOdometer)}'),
        ),
      );
}
