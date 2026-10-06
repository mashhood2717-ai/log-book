import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../models.dart';

final dateTimeFmt = DateFormat('dd MMM yyyy, hh:mm a');
final dateFmt = DateFormat('dd MMM yyyy');
final numFmt = NumberFormat('#,##0');
final moneyFmt = NumberFormat('#,##0.##');

String km(int? v) => v == null ? '–' : '${numFmt.format(v)} km';

/// Odometer field check – digits only, and a sane upper limit.
String? odometerValidator(String? v) {
  final n = int.tryParse(v ?? '');
  if (n == null) return 'Enter odometer reading';
  if (n > 9999999) return 'Reading looks too large';
  return null;
}

/// "3h 20m", "2d 4h", "45m"
String durationText(Duration d) {
  if (d.isNegative) d = Duration.zero;
  if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
  if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
  return '${d.inMinutes}m';
}

/// Opens a GPS point in Google Maps (app or browser).
Future<void> openMap(BuildContext context, GeoPoint p) async {
  final ok = await launchUrl(p.mapsUrl, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open maps. Location: $p')));
  }
}

/// "📍 View on map" button, or a grey note when no GPS was captured.
class LocationLink extends StatelessWidget {
  final GeoPoint? point;
  const LocationLink(this.point, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = point;
    if (p == null) {
      return Text('Not captured',
          style: TextStyle(color: Colors.grey.shade600));
    }
    return InkWell(
      onTap: () => openMap(context, p),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.place, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              'View on map'
              '${p.accuracy == null ? '' : '  (±${p.accuracy!.round()} m)'}',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.underline),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Compact row used in trip lists.
class TripTile extends StatelessWidget {
  final Trip trip;
  final bool showDriver;
  const TripTile({super.key, required this.trip, this.showDriver = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              trip.isOngoing ? Colors.orange.shade100 : scheme.primaryContainer,
          child: Icon(trip.isOngoing ? Icons.directions_car : Icons.check,
              color: trip.isOngoing ? Colors.orange.shade800 : scheme.primary),
        ),
        title: Text(trip.destination,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${dateFmt.format(trip.startTime)} · ${trip.vehicleRegNo}'
          '${showDriver ? ' · ${trip.driverName}' : ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(trip.isOngoing ? 'Open' : km(trip.distanceKm),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        onTap: () => showTripDetails(context, trip),
      ),
    );
  }
}

/// Bottom sheet with every detail of a trip.
void showTripDetails(BuildContext context, Trip t) {
  Widget rowWidget(String label, Widget value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 120,
                child:
                    Text(label, style: TextStyle(color: Colors.grey.shade600))),
            Expanded(child: value),
          ],
        ),
      );
  Widget row(String label, String value) => rowWidget(label,
      Text(value, style: const TextStyle(fontWeight: FontWeight.w500)));

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Trip #${t.id}',
                style: Theme.of(context).textTheme.titleLarge),
            const Divider(),
            row('Driver', t.driverName),
            row('Vehicle', t.vehicleRegNo),
            row('Purpose', t.purpose),
            row('Destination', t.destination),
            row('Started', dateTimeFmt.format(t.startTime)),
            row('Start mileage', km(t.startMileage)),
            rowWidget('Start location', LocationLink(t.startLocation)),
            row(
                'Returned',
                t.endTime == null
                    ? 'Trip still open'
                    : dateTimeFmt.format(t.endTime!)),
            row('End mileage', km(t.endMileage)),
            if (!t.isOngoing)
              rowWidget('End location', LocationLink(t.endLocation)),
            row('Distance', km(t.distanceKm)),
            row(t.isOngoing ? 'Out for' : 'Duration',
                durationText(t.duration)),
            row(
                'Fuel added',
                t.fuelLitres == null
                    ? '–'
                    : '${moneyFmt.format(t.fuelLitres)} L'),
            row(
                'Fuel cost',
                t.fuelCost == null
                    ? '–'
                    : '${AppConfig.currency} ${moneyFmt.format(t.fuelCost)}'),
            row('Notes',
                (t.notes == null || t.notes!.isEmpty) ? '–' : t.notes!),
          ],
        ),
      ),
    ),
  );
}
