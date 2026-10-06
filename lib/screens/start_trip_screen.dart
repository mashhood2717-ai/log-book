import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../services/db.dart';
import '../widgets/location_capture.dart';
import '../widgets/trip_widgets.dart';

class StartTripScreen extends StatefulWidget {
  const StartTripScreen({super.key});

  @override
  State<StartTripScreen> createState() => _StartTripScreenState();
}

class _StartTripScreenState extends State<StartTripScreen> {
  final _form = GlobalKey<FormState>();
  final _mileage = TextEditingController();
  final _purpose = TextEditingController();
  final _destination = TextEditingController();
  late Future<List<Vehicle>> _vehicles;
  final _location = LocationCapture();
  Vehicle? _vehicle;
  String? _prefilled; // mileage text we filled in, so we don't overwrite typing
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _vehicles = Db.vehicles(activeOnly: true);
  }

  @override
  void dispose() {
    _mileage.dispose();
    _purpose.dispose();
    _destination.dispose();
    _location.dispose();
    super.dispose();
  }

  void _pickVehicle(Vehicle? v) {
    setState(() => _vehicle = v);
    // Pre-fill with the reading the vehicle was last returned at,
    // unless the driver has already typed their own reading.
    final untouched = _mileage.text.isEmpty || _mileage.text == _prefilled;
    if (untouched) {
      _prefilled = (v != null && v.lastOdometer > 0)
          ? v.lastOdometer.toString()
          : '';
      _mileage.text = _prefilled!;
    }
  }

  Future<bool> _confirm(String msg) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Please confirm'),
          content: Text(msg),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Fix it')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Continue')),
          ],
        ),
      ) ??
      false;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final start = int.parse(_mileage.text);
    final v = _vehicle!;
    if (v.lastOdometer > 0 && start < v.lastOdometer) {
      final ok = await _confirm(
          'Start mileage ${km(start)} is LESS than this vehicle\'s last recorded reading '
          '${km(v.lastOdometer)}. Continue anyway?');
      if (!ok) return;
    } else if (v.lastOdometer > 0 && start - v.lastOdometer > 50) {
      final ok = await _confirm(
          'Start mileage is ${km(start - v.lastOdometer)} more than the last recorded reading '
          '${km(v.lastOdometer)}. The vehicle may have been used without a log entry. Continue?');
      if (!ok) return;
    }
    if (!mounted) return;

    setState(() => _busy = true);
    try {
      final (proceed, point) = await _location.resolve(context);
      if (!proceed) return;
      await Db.startTrip(
        vehicleId: v.id,
        startMileage: start,
        purpose: _purpose.text,
        destination: _destination.text,
        location: point,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(Db.friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Start trip')),
      body: FutureBuilder<List<Vehicle>>(
        future: _vehicles,
        builder: (context, snap) {
          if (!snap.hasData && !snap.hasError) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text(Db.friendlyError(snap.error!)));
          }
          final list = snap.data!;
          if (list.isEmpty) {
            return const Center(
                child: Text('No vehicles yet. Ask your admin to add one.'));
          }
          return Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<Vehicle>(
                  initialValue: _vehicle,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Vehicle',
                      prefixIcon: Icon(Icons.directions_car)),
                  items: list
                      .map((v) =>
                          DropdownMenuItem(value: v, child: Text(v.label)))
                      .toList(),
                  onChanged: _pickVehicle,
                  validator: (v) => v == null ? 'Select a vehicle' : null,
                ),
                if (_vehicle != null && _vehicle!.lastOdometer > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 12),
                    child: Text(
                        'Last recorded reading: ${km(_vehicle!.lastOdometer)}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _mileage,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                      labelText: 'Start mileage (odometer km)',
                      prefixIcon: Icon(Icons.speed)),
                  validator: odometerValidator,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _purpose,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                      labelText: 'Purpose',
                      hintText: 'e.g. AWS maintenance visit',
                      prefixIcon: Icon(Icons.work_outline)),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter purpose' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _destination,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                      labelText: 'Destination',
                      hintText: 'e.g. Nowshera',
                      prefixIcon: Icon(Icons.place_outlined)),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Enter destination'
                      : null,
                ),
                const SizedBox(height: 8),
                LocationStatusTile(_location),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _submit,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(_busy ? 'Starting…' : 'Start trip'),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
