import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../models.dart';
import '../screens/edit_trip_screen.dart';
import '../services/db.dart';
import 'brand.dart';

final dateTimeFmt = DateFormat('dd MMM yyyy, hh:mm a');
final dateFmt = DateFormat('dd MMM yyyy');
final timeFmt = DateFormat('hh:mm a');
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
          style: TextStyle(color: context.colors.muted));
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

  /// Called after the trip was edited or deleted from its details sheet.
  final VoidCallback? onChanged;
  const TripTile(
      {super.key, required this.trip, this.showDriver = false, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final open = trip.isOngoing;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 4, 16, 4),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: open ? Brand.sunGradient : Brand.blueGradient,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(open ? Icons.directions_car : Icons.check_rounded,
              color: Colors.white),
        ),
        title: Text(trip.destination,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontWeight: FontWeight.w700, color: context.colors.ink)),
        subtitle: Text(
          '${dateFmt.format(trip.startTime)} · ${trip.vehicleRegNo}'
          '${showDriver ? ' · ${trip.driverName}' : ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: open
            ? Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Brand.orange.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('OUT',
                    style: TextStyle(
                        color: context.colors.amberText,
                        fontWeight: FontWeight.w800,
                        fontSize: 12)),
              )
            : Text(km(trip.distanceKm),
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: context.colors.accent,
                    fontSize: 15)),
        onTap: () async {
          if (await showTripDetails(context, trip)) onChanged?.call();
        },
      ),
    );
  }
}

/// Bottom sheet with every detail of a trip.
///
/// Shows Edit (driver/admin, within 24 h of the end) and Delete (admin).
/// Returns true if the trip was edited or deleted, so lists can refresh.
Future<bool> showTripDetails(BuildContext context, Trip t) async {
  Widget rowWidget(String label, Widget value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 120,
                child:
                    Text(label, style: TextStyle(color: context.colors.muted))),
            Expanded(child: value),
          ],
        ),
      );
  Widget row(String label, String value) => rowWidget(label,
      Text(value, style: const TextStyle(fontWeight: FontWeight.w500)));

  final canEdit = Db.canEdit(t);
  final left = Db.editTimeLeft(t);
  final action = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('Trip #${t.id}',
                  style: Theme.of(context).textTheme.titleLarge),
              if (t.editedAt != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Brand.orange.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('EDITED',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: context.colors.amberText)),
                ),
              ],
            ]),
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
            if (t.editedAt != null)
              row('Last edited', dateTimeFmt.format(t.editedAt!)),
            if (canEdit || Db.isAdmin) ...[
              const SizedBox(height: 16),
              Row(children: [
                if (canEdit)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(sheet, 'edit'),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit trip'),
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50)),
                    ),
                  ),
                if (canEdit && Db.isAdmin) const SizedBox(width: 12),
                if (Db.isAdmin)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(sheet, 'delete'),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        foregroundColor: Theme.of(context).colorScheme.error,
                        side: BorderSide(
                            color: Theme.of(context)
                                .colorScheme
                                .error
                                .withValues(alpha: 0.5)),
                      ),
                    ),
                  ),
              ]),
              if (canEdit && left != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                      'Can be edited for another ${durationText(left)}.',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              if (!canEdit && !t.isOngoing && t.driverId == Db.uid)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                      'Editing closed – more than 24 hours since the trip ended.',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
            ],
          ],
        ),
      ),
    ),
  );
  if (!context.mounted || action == null) return false;

  if (action == 'edit') {
    final saved = await Navigator.push<bool>(context,
        MaterialPageRoute(builder: (_) => EditTripScreen(trip: t)));
    return saved == true;
  }

  // Delete (admin)
  final sure = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Delete trip #${t.id}?'),
      content: Text('${t.vehicleRegNo} → ${t.destination}, '
          '${dateFmt.format(t.startTime)} by ${t.driverName}.\n\n'
          'This permanently removes the trip. It cannot be undone.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: Theme.of(c).colorScheme.error),
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (sure != true || !context.mounted) return false;
  try {
    await Db.deleteTrip(t.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Trip #${t.id} deleted')));
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(Db.friendlyError(e))));
    }
    return false;
  }
}
