import 'package:flutter/material.dart';

import '../models.dart';
import '../services/location.dart';

/// Holds the GPS reading for a start/end trip form. Starts reading as soon as
/// it is created so the fix is usually ready by the time the driver submits.
class LocationCapture extends ChangeNotifier {
  Future<LocationResult>? _pending;
  LocationResult? result;

  LocationCapture() {
    refresh();
  }

  bool get busy => _pending != null;

  Future<LocationResult> refresh() {
    final f = _pending ??= LocationService.current().then((r) {
      result = r;
      _pending = null;
      notifyListeners();
      return r;
    });
    notifyListeners();
    return f;
  }

  /// Waits for the reading. If there is none, asks the driver whether to retry
  /// or carry on without it. Returns `(proceed, point)`.
  Future<(bool, GeoPoint?)> resolve(BuildContext context) async {
    while (true) {
      final pending = _pending;
      final LocationResult? r = pending != null ? await pending : result;
      if (r?.point != null) return (true, r!.point);
      if (!context.mounted) return (false, null);
      final choice = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Location not recorded'),
          content: Text('${r?.problem ?? 'No GPS reading.'}\n\n'
              'Your manager will see that this trip has no location.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, 'skip'),
                child: const Text('Continue without')),
            FilledButton(
                onPressed: () => Navigator.pop(c, 'retry'),
                child: const Text('Try again')),
          ],
        ),
      );
      if (choice == 'skip') return (true, null);
      if (choice != 'retry') return (false, null); // dialog dismissed
      refresh();
    }
  }
}

/// One-line status of the GPS reading, with a retry / settings action.
class LocationStatusTile extends StatelessWidget {
  final LocationCapture capture;
  const LocationStatusTile(this.capture, {super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: capture,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        if (capture.busy) {
          return const ListTile(
            dense: true,
            leading: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2)),
            title: Text('Getting location…'),
          );
        }
        final r = capture.result;
        final p = r?.point;
        if (p != null) {
          return ListTile(
            dense: true,
            leading: Icon(Icons.my_location, color: scheme.primary),
            title: const Text('Location recorded'),
            subtitle: Text(p.accuracy == null
                ? p.toString()
                : 'Accurate to about ${p.accuracy!.round()} m'),
          );
        }
        return ListTile(
          dense: true,
          leading: Icon(Icons.location_off, color: scheme.error),
          title: Text(r?.problem ?? 'Location not available'),
          trailing: Wrap(children: [
            IconButton(
                tooltip: 'Location settings',
                icon: const Icon(Icons.settings),
                onPressed: LocationService.openSettings),
            IconButton(
                tooltip: 'Try again',
                icon: const Icon(Icons.refresh),
                onPressed: capture.refresh),
          ]),
        );
      },
    );
  }
}
