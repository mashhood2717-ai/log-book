import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../config.dart';
import '../models.dart';
import '../services/db.dart';
import '../widgets/animations.dart';
import '../widgets/brand.dart';
import '../widgets/trip_widgets.dart';

/// Admin view: all drivers' trips for a month, with totals and CSV export.
class AdminTripsScreen extends StatefulWidget {
  const AdminTripsScreen({super.key});

  @override
  State<AdminTripsScreen> createState() => _AdminTripsScreenState();
}

class _AdminTripsScreenState extends State<AdminTripsScreen> {
  final _monthFmt = DateFormat('MMMM yyyy');
  late DateTime _month; // first day of the selected month
  int? _vehicleId; // null = all vehicles
  List<Vehicle> _vehicles = [];
  List<Trip> _trips = [];
  bool _loading = true;
  String? _error;
  int _loadSeq = 0; // ignore results of older loads (fast month taps)

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _init();
  }

  Future<void> _init() async {
    try {
      final list = await Db.vehicles();
      if (mounted) setState(() => _vehicles = list);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Vehicle filter unavailable: ${Db.friendlyError(e)}')));
      }
    }
    await _load();
  }

  Future<void> _load() async {
    final seq = ++_loadSeq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final trips = await Db.allTrips(
        from: _month,
        to: DateTime(_month.year, _month.month + 1),
        vehicleId: _vehicleId,
      );
      if (mounted && seq == _loadSeq) setState(() => _trips = trips);
    } catch (e) {
      if (mounted && seq == _loadSeq) {
        setState(() => _error = Db.friendlyError(e));
      }
    } finally {
      if (mounted && seq == _loadSeq) setState(() => _loading = false);
    }
  }

  void _shiftMonth(int delta) {
    _month = DateTime(_month.year, _month.month + delta);
    _load();
  }

  String _csvCell(Object? v) {
    var s = v?.toString() ?? '';
    // Stop Excel from running driver-typed text as a formula.
    if (v is String && s.isNotEmpty && '=+-@\t\r'.contains(s[0])) {
      s = "'$s";
    }
    return (s.contains(',') || s.contains('"') || s.contains('\n'))
        ? '"${s.replaceAll('"', '""')}"'
        : s;
  }

  Future<void> _exportCsv() async {
    final f = DateFormat('yyyy-MM-dd HH:mm');
    final rows = <List<Object?>>[
      [
        'Trip ID',
        'Driver',
        'Vehicle',
        'Status',
        'Purpose',
        'Destination',
        'Start time',
        'Start mileage',
        'End time',
        'End mileage',
        'Distance (km)',
        'Duration (h)',
        'Fuel (L)',
        'Fuel cost (${AppConfig.currency})',
        'Notes',
        'Start location',
        'End location',
      ],
      ..._trips.reversed.map((t) => [
            t.id,
            t.driverName,
            t.vehicleRegNo,
            t.status,
            t.purpose,
            t.destination,
            f.format(t.startTime),
            t.startMileage,
            t.endTime == null ? '' : f.format(t.endTime!),
            t.endMileage,
            t.distanceKm,
            t.isOngoing
                ? ''
                : (t.duration.inMinutes / 60).toStringAsFixed(1),
            t.fuelLitres,
            t.fuelCost,
            t.notes,
            t.startLocation?.mapsUrl,
            t.endLocation?.mapsUrl,
          ]),
    ];
    final csv = rows.map((r) => r.map(_csvCell).join(',')).join('\r\n');

    final dir = await getTemporaryDirectory();
    final name = 'trips_${DateFormat('yyyy_MM').format(_month)}.csv';
    final file = File('${dir.path}/$name');
    // BOM so Excel reads it as UTF-8 (Urdu names, dashes etc.)
    await file.writeAsString('\uFEFF$csv');
    await Share.shareXFiles([XFile(file.path, mimeType: 'text/csv')],
        subject: 'Trip log – ${_monthFmt.format(_month)}');
  }

  @override
  Widget build(BuildContext context) {
    final done = _trips.where((t) => !t.isOngoing);
    final totalKm = done.fold<int>(0, (s, t) => s + (t.distanceKm ?? 0));
    final totalL = _trips.fold<double>(0, (s, t) => s + (t.fuelLitres ?? 0));
    final totalCost = _trips.fold<double>(0, (s, t) => s + (t.fuelCost ?? 0));

    return Scaffold(
      appBar: AppBar(
        title: const Text('All trips'),
        actions: [
          IconButton(
            tooltip: 'Export CSV',
            icon: const Icon(Icons.download),
            onPressed: _trips.isEmpty ? null : _exportCsv,
          ),
        ],
      ),
      body: Column(
        children: [
          // Month selector
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                  onPressed: () => _shiftMonth(-1),
                  icon: const Icon(Icons.chevron_left)),
              Text(_monthFmt.format(_month),
                  style: Theme.of(context).textTheme.titleMedium),
              IconButton(
                  onPressed: () => _shiftMonth(1),
                  icon: const Icon(Icons.chevron_right)),
            ],
          ),
          // Vehicle filter
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DropdownButtonFormField<int?>(
              initialValue: _vehicleId,
              isExpanded: true,
              decoration:
                  const InputDecoration(labelText: 'Vehicle', isDense: true),
              items: [
                const DropdownMenuItem<int?>(
                    value: null, child: Text('All vehicles')),
                ..._vehicles.map((v) =>
                    DropdownMenuItem<int?>(value: v.id, child: Text(v.label))),
              ],
              onChanged: (v) {
                _vehicleId = v;
                _load();
              },
            ),
          ),
          // Totals
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              _stat('Trips', _trips.length, (v) => numFmt.format(v)),
              _stat('Km', totalKm, (v) => numFmt.format(v)),
              _stat('Fuel L', totalL, (v) => moneyFmt.format(v)),
              _stat(AppConfig.currency, totalCost,
                  (v) => NumberFormat.compact().format(v)),
            ]),
          ),
          const Divider(height: 1),
          Expanded(child: _list()),
        ],
      ),
    );
  }

  Widget _stat(String label, num value, String Function(num) format) =>
      Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            color: context.colors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.colors.border),
          ),
          child: Column(children: [
            FittedBox(
              child: CountUp(
                value: value,
                format: format,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: context.colors.accent),
              ),
            ),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    color: context.colors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      );

  Widget _list() {
    if (_loading) return const Center(child: BrandLoader(label: 'Loading trips…'));
    if (_error != null) return Center(child: Text(_error!));
    if (_trips.isEmpty) {
      return const Center(child: Text('No trips this month.'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 6, bottom: 24),
        itemCount: _trips.length,
        itemBuilder: (_, i) => FadeSlideIn(
            index: i,
            child: TripTile(
                trip: _trips[i], showDriver: true, onChanged: _load)),
      ),
    );
  }
}
