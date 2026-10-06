import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../services/db.dart';
import '../widgets/trip_widgets.dart';

/// Admin: add vehicles, correct odometer, mark vehicles inactive.
class VehiclesScreen extends StatefulWidget {
  const VehiclesScreen({super.key});

  @override
  State<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends State<VehiclesScreen> {
  late Future<List<Vehicle>> _future;

  @override
  void initState() {
    super.initState();
    _future = Db.vehicles();
  }

  void _reload() => setState(() => _future = Db.vehicles());

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _edit([Vehicle? v]) async {
    final reg = TextEditingController(text: v?.regNo);
    final desc = TextEditingController(text: v?.description);
    final odo = TextEditingController(text: v?.lastOdometer.toString() ?? '0');
    final key = GlobalKey<FormState>();

    final save = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(v == null ? 'Add vehicle' : 'Edit ${v.regNo}'),
        content: Form(
          key: key,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: reg,
              enabled: v == null,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Registration no.'),
              validator: (s) =>
                  (s == null || s.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: desc,
              decoration:
                  const InputDecoration(labelText: 'Description (make/model)'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: odo,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration:
                  const InputDecoration(labelText: 'Current odometer (km)'),
              validator: odometerValidator,
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (key.currentState!.validate()) Navigator.pop(c, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final regText = reg.text, descText = desc.text, odoText = odo.text;
    if (save != true) return;

    try {
      if (v == null) {
        await Db.addVehicle(regText, descText, int.parse(odoText));
      } else {
        await Db.updateVehicle(v.id, {
          'description': descText.trim(),
          'last_odometer': int.parse(odoText),
        });
      }
      if (mounted) _reload();
    } catch (e) {
      _snack(Db.friendlyError(e));
    }
  }

  Future<void> _toggle(Vehicle v, bool active) async {
    try {
      await Db.updateVehicle(v.id, {'active': active});
      if (mounted) _reload();
    } catch (e) {
      _snack(Db.friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vehicles')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Add vehicle'),
      ),
      body: FutureBuilder<List<Vehicle>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text(Db.friendlyError(snap.error!)));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data!;
          if (list.isEmpty) {
            return const Center(child: Text('No vehicles yet.'));
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 90),
            children: list
                .map((v) => Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      child: ListTile(
                        title: Text(v.regNo,
                            style: TextStyle(
                                color: v.active ? null : Colors.grey)),
                        subtitle: Text(
                            '${v.description ?? ''}\nOdometer: ${km(v.lastOdometer)}'),
                        isThreeLine: true,
                        onTap: () => _edit(v),
                        trailing: Switch(
                            value: v.active, onChanged: (a) => _toggle(v, a)),
                      ),
                    ))
                .toList(),
          );
        },
      ),
    );
  }
}
