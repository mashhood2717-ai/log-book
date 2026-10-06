import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../models.dart';
import '../services/db.dart';
import '../widgets/location_capture.dart';
import '../widgets/trip_widgets.dart';

class EndTripScreen extends StatefulWidget {
  final Trip trip;
  const EndTripScreen({super.key, required this.trip});

  @override
  State<EndTripScreen> createState() => _EndTripScreenState();
}

class _EndTripScreenState extends State<EndTripScreen> {
  final _form = GlobalKey<FormState>();
  final _mileage = TextEditingController();
  final _litres = TextEditingController();
  final _cost = TextEditingController();
  final _notes = TextEditingController();
  final _location = LocationCapture();
  bool _busy = false;

  @override
  void dispose() {
    _mileage.dispose();
    _litres.dispose();
    _cost.dispose();
    _notes.dispose();
    _location.dispose();
    super.dispose();
  }

  int? get _distance {
    final end = int.tryParse(_mileage.text);
    return end == null ? null : end - widget.trip.startMileage;
  }

  double? _num(String s) => s.trim().isEmpty ? null : double.tryParse(s.trim());

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final dist = _distance!;
    if (dist > 1000) {
      final ok = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Please confirm'),
              content: Text(
                  'This trip shows ${km(dist)}. Is the end mileage correct?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Fix it')),
                FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Yes')),
              ],
            ),
          ) ??
          false;
      if (!ok) return;
    }
    if (!mounted) return;

    setState(() => _busy = true);
    try {
      final (proceed, point) = await _location.resolve(context);
      if (!proceed) return;
      await Db.endTrip(
        tripId: widget.trip.id,
        endMileage: int.parse(_mileage.text),
        fuelLitres: _num(_litres.text),
        fuelCost: _num(_cost.text),
        notes: _notes.text,
        location: point,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(Db.friendlyError(e))));
        // Trip was closed elsewhere – go back so Home shows the real state.
        if (e is AppException) Navigator.pop(context, true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _decimalValidator(String? v) {
    if (v == null || v.trim().isEmpty) return null; // optional
    final d = double.tryParse(v.trim());
    if (d == null || d < 0) return 'Enter a valid number';
    if (d > 9999999) return 'Too large';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.trip;
    final dist = _distance;
    final decimal = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
    return Scaffold(
      appBar: AppBar(title: const Text('End trip')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.directions_car),
                title: Text('${t.vehicleRegNo} → ${t.destination}'),
                subtitle: Text('Started ${dateTimeFmt.format(t.startTime)}\n'
                    'Start mileage: ${km(t.startMileage)}'),
                isThreeLine: true,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _mileage,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                  labelText: 'End mileage (odometer km)',
                  prefixIcon: Icon(Icons.speed)),
              onChanged: (_) => setState(() {}),
              validator: (v) {
                final err = odometerValidator(v);
                if (err != null) return err;
                if (int.parse(v!) < t.startMileage) {
                  return 'Cannot be less than start mileage (${numFmt.format(t.startMileage)})';
                }
                return null;
              },
            ),
            if (dist != null && dist >= 0)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 12),
                child: Text('Distance travelled: ${km(dist)}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary)),
              ),
            const SizedBox(height: 24),
            Text('Fuel (leave blank if none)',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _litres,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: decimal,
                  decoration: const InputDecoration(
                      labelText: 'Litres',
                      prefixIcon: Icon(Icons.local_gas_station)),
                  validator: _decimalValidator,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _cost,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: decimal,
                  decoration: const InputDecoration(
                      labelText: 'Cost (${AppConfig.currency})'),
                  validator: _decimalValidator,
                ),
              ),
            ]),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notes,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Trip details / remarks',
                hintText: 'Work done, stops, tolls, vehicle issues…',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            LocationStatusTile(_location),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: const Icon(Icons.flag),
              label: Text(_busy ? 'Saving…' : 'End trip'),
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
            ),
          ],
        ),
      ),
    );
  }
}
