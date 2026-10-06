import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../models.dart';
import '../services/db.dart';
import '../widgets/animations.dart';
import '../widgets/brand.dart';
import '../widgets/trip_widgets.dart';

/// Correct a trip's details. Times, GPS points, vehicle and driver are fixed
/// (the database enforces this too); finished trips can be corrected for 24 h.
class EditTripScreen extends StatefulWidget {
  final Trip trip;
  const EditTripScreen({super.key, required this.trip});

  @override
  State<EditTripScreen> createState() => _EditTripScreenState();
}

class _EditTripScreenState extends State<EditTripScreen> {
  final _form = GlobalKey<FormState>();
  late final Trip t = widget.trip;
  late final _startMileage =
      TextEditingController(text: t.startMileage.toString());
  late final _endMileage =
      TextEditingController(text: t.endMileage?.toString() ?? '');
  late final _purpose = TextEditingController(text: t.purpose);
  late final _destination = TextEditingController(text: t.destination);
  late final _litres = TextEditingController(text: _numText(t.fuelLitres));
  late final _cost = TextEditingController(text: _numText(t.fuelCost));
  late final _notes = TextEditingController(text: t.notes ?? '');
  bool _busy = false;

  static String _numText(double? v) => v == null
      ? ''
      : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());

  @override
  void dispose() {
    for (final c in [
      _startMileage,
      _endMileage,
      _purpose,
      _destination,
      _litres,
      _cost,
      _notes
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _num(String s) => s.trim().isEmpty ? null : double.tryParse(s.trim());

  String? _decimalValidator(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final d = double.tryParse(v.trim());
    if (d == null || d < 0) return 'Enter a valid number';
    if (d > 9999999) return 'Too large';
    return null;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final values = <String, dynamic>{
      'start_mileage': int.parse(_startMileage.text),
      'purpose': _purpose.text.trim(),
      'destination': _destination.text.trim(),
      if (!t.isOngoing) ...{
        'end_mileage': int.parse(_endMileage.text),
        'fuel_litres': _num(_litres.text),
        'fuel_cost': _num(_cost.text),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      },
    };
    setState(() => _busy = true);
    try {
      await Db.updateTrip(t.id, values);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Trip updated')));
      Navigator.pop(context, true);
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
    final left = Db.editTimeLeft(t);
    final digits = [FilteringTextInputFormatter.digitsOnly];
    final decimal = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
    var i = 0; // stagger index for the entrance animation
    Widget anim(Widget w) => FadeSlideIn(index: i++, child: w);

    return Scaffold(
      appBar: AppBar(title: Text('Edit trip #${t.id}')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            anim(Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Brand.blue.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline, color: Brand.blue),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${t.vehicleRegNo} · ${t.driverName}\n'
                    'Times and GPS locations can\'t be changed.'
                    '${left == null ? '' : '\nYou can edit this trip for another ${durationText(left)}.'}',
                    style: const TextStyle(color: Brand.ink, height: 1.35),
                  ),
                ),
              ]),
            )),
            const SizedBox(height: 18),
            anim(TextFormField(
              controller: _startMileage,
              keyboardType: TextInputType.number,
              inputFormatters: digits,
              decoration: const InputDecoration(
                  labelText: 'Start mileage (km)',
                  prefixIcon: Icon(Icons.speed)),
              validator: odometerValidator,
            )),
            if (!t.isOngoing) ...[
              const SizedBox(height: 14),
              anim(TextFormField(
                controller: _endMileage,
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                decoration: const InputDecoration(
                    labelText: 'End mileage (km)',
                    prefixIcon: Icon(Icons.flag_outlined)),
                validator: (v) {
                  final err = odometerValidator(v);
                  if (err != null) return err;
                  final start = int.tryParse(_startMileage.text);
                  if (start != null && int.parse(v!) < start) {
                    return 'Cannot be less than start mileage';
                  }
                  return null;
                },
              )),
            ],
            const SizedBox(height: 14),
            anim(TextFormField(
              controller: _purpose,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Purpose', prefixIcon: Icon(Icons.work_outline)),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter purpose' : null,
            )),
            const SizedBox(height: 14),
            anim(TextFormField(
              controller: _destination,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Destination',
                  prefixIcon: Icon(Icons.place_outlined)),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter destination' : null,
            )),
            if (!t.isOngoing) ...[
              const SizedBox(height: 14),
              anim(Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _litres,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: decimal,
                    decoration: const InputDecoration(
                        labelText: 'Fuel (L)',
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
              ])),
              const SizedBox(height: 14),
              anim(TextFormField(
                controller: _notes,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    labelText: 'Trip details / remarks',
                    alignLabelWithHint: true),
              )),
            ],
            const SizedBox(height: 24),
            anim(FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_busy ? 'Saving…' : 'Save changes'),
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54)),
            )),
          ],
        ),
      ),
    );
  }
}
