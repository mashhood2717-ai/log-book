import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'brand.dart';

/// Peshawar – where the map opens when there's nothing to show yet.
const defaultCenter = LatLng(34.0151, 71.5249);

/// OpenStreetMap tiles (free, no key) + the required attribution.
List<Widget> baseMapLayers(BuildContext context) => [
      TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.weatherwalay.trip_logbook',
        maxNativeZoom: 19,
      ),
      RichAttributionWidget(
        alignment: AttributionAlignment.bottomLeft,
        attributions: [
          TextSourceAttribution('OpenStreetMap contributors',
              onTap: () => launchUrl(
                  Uri.parse('https://openstreetmap.org/copyright'),
                  mode: LaunchMode.externalApplication)),
        ],
      ),
    ];

/// Camera that shows all [points] (or the default place if there are none).
MapOptions fitOptions(List<LatLng> points, {double maxZoom = 16}) {
  if (points.isEmpty) {
    return const MapOptions(initialCenter: defaultCenter, initialZoom: 9);
  }
  return MapOptions(
    initialCameraFit: CameraFit.coordinates(
      coordinates: points,
      padding: const EdgeInsets.all(56),
      maxZoom: maxZoom,
    ),
  );
}

/// Round pin with an icon, used for start / end / vehicle markers.
class MapPin extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String? label;
  const MapPin({super.key, required this.icon, required this.color, this.label});

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (label != null)
        Container(
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
          child: Text(label!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w800, color: Brand.ink)),
        ),
      Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    ]);
  }
}

/// "just now", "4 min ago", "2 h ago", "3 days ago".
String agoText(DateTime t, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${d.inDays} day${d.inDays == 1 ? '' : 's'} ago';
}
