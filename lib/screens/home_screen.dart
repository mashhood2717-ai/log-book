import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/db.dart';
import '../services/reminders.dart';
import '../services/theme_settings.dart';
import '../widgets/animations.dart';
import '../widgets/brand.dart';
import '../widgets/trip_widgets.dart';
import 'admin_trips_screen.dart';
import 'edit_trip_screen.dart';
import 'end_trip_screen.dart';
import 'fleet_screen.dart';
import 'start_trip_screen.dart';
import 'users_screen.dart';
import 'vehicles_screen.dart';

class _HomeData {
  final Profile profile;
  final Trip? openTrip;
  final List<Trip> recent;
  _HomeData(this.profile, this.openTrip, this.recent);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<_HomeData> _future;
  Timer? _tick; // keeps the "out for" timer on the open-trip card current

  @override
  void initState() {
    super.initState();
    _future = _load();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<_HomeData> _load() async {
    final results = await Future.wait(
        [Db.myProfile(), Db.myOpenTrip(), Db.myRecentTrips()]);
    final data = _HomeData(
        results[0] as Profile, results[1] as Trip?, results[2] as List<Trip>);
    _openTrip = data.openTrip;
    // Keep the 11 AM / 5 PM reminders scheduled, worded for the current trip.
    Reminders.sync(openTrip: data.openTrip);
    return data;
  }

  Trip? _openTrip; // last loaded, for the reminder settings

  Future<void> _refresh() async {
    final f = _load();
    setState(() => _future = f);
    await f;
  }

  Future<void> _open(Widget screen) async {
    final changed = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => screen));
    if (changed == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_HomeData>(
      future: _future,
      builder: (context, snap) {
        final data = snap.data;
        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 68,
            titleSpacing: 16,
            title: Row(children: [
              const BrandMark(width: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('WEATHERWALAY DEPLOYMENT',
                        style: TextStyle(
                            fontSize: 10.5,
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w700,
                            color: context.colors.muted)),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        data == null
                            ? 'Trip Logbook'
                            : 'Hi, ${data.profile.fullName.split(' ').first}',
                        key: ValueKey(data == null),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ]),
            actions: [
              if (data?.profile.isAdmin == true) ...[
                IconButton(
                  tooltip: 'Fleet status',
                  icon: const Icon(Icons.dashboard_outlined),
                  onPressed: () => _open(const FleetScreen()),
                ),
                IconButton(
                  tooltip: 'All trips',
                  icon: const Icon(Icons.table_chart_outlined),
                  onPressed: () => _open(const AdminTripsScreen()),
                ),
              ],
              _menu(isAdmin: data?.profile.isAdmin == true),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _refresh,
            child: _body(snap),
          ),
        );
      },
    );
  }

  /// ⋮ menu: admin tools (admins only), appearance, sign out.
  Widget _menu({required bool isAdmin}) {
    PopupMenuItem<String> item(String value, IconData icon, String text) =>
        PopupMenuItem(
          value: value,
          child: ListTile(leading: Icon(icon), title: Text(text)),
        );
    return PopupMenuButton<String>(
      onSelected: (v) => switch (v) {
        'vehicles' => _open(const VehiclesScreen()),
        'users' => _open(const UsersScreen()),
        'appearance' => ThemeSettings.showPicker(context),
        'reminders' => Reminders.showSettings(context, openTrip: _openTrip),
        _ => Db.signOut(),
      },
      itemBuilder: (_) => [
        if (isAdmin) ...[
          item('vehicles', Icons.directions_car_outlined, 'Vehicles'),
          item('users', Icons.people_outline, 'Drivers & users'),
          const PopupMenuDivider(),
        ],
        item('reminders', Icons.notifications_outlined, 'Reminders'),
        item('appearance', ThemeSettings.icon(ThemeSettings.mode.value),
            'Appearance'),
        item('signout', Icons.logout, 'Sign out'),
      ],
    );
  }

  Widget _body(AsyncSnapshot<_HomeData> snap) {
    if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
      // Inside a ListView so pull-to-refresh still works while loading.
      return const BrandLoaderList(label: 'Loading your trips…');
    }
    if (snap.hasError) {
      return ListView(children: [
        FadeSlideIn(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(children: [
              Icon(Icons.cloud_off,
                  size: 56, color: context.colors.faint),
              const SizedBox(height: 12),
              Text(Db.friendlyError(snap.error!), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry')),
            ]),
          ),
        ),
      ]);
    }
    final d = snap.data!;
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
          child: FadeSlideIn(
            offset: 30,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: d.openTrip == null
                  ? _startCard()
                  : _openTripCard(d.openTrip!),
            ),
          ),
        ),
        FadeSlideIn(
          index: 2,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
            child: Row(children: [
              Text('My recent trips',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: context.colors.ink)),
              const Spacer(),
              if (d.recent.isNotEmpty)
                Text('${d.recent.length}',
                    style: TextStyle(color: context.colors.muted)),
            ]),
          ),
        ),
        if (d.recent.isEmpty)
          FadeSlideIn(
            index: 3,
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(children: [
                Icon(Icons.route,
                    size: 44, color: context.colors.faint),
                const SizedBox(height: 8),
                Text('No completed trips yet.',
                    style: TextStyle(color: context.colors.muted)),
              ]),
            ),
          ),
        for (final (i, t) in d.recent.indexed)
          FadeSlideIn(
              index: i + 3, child: TripTile(trip: t, onChanged: _refresh)),
      ],
    );
  }

  Widget _startCard() {
    return _HeroCard(
      key: const ValueKey('start'),
      gradient: Brand.blueGradient,
      shadow: Brand.blue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ready to roll?',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('No trip in progress',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8))),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.route, color: Colors.white, size: 30),
            ),
          ]),
          const SizedBox(height: 20),
          _CardButton(
            label: 'Start a trip',
            icon: Icons.play_arrow_rounded,
            color: Brand.blue,
            onPressed: () => _open(const StartTripScreen()),
          ),
        ],
      ),
    );
  }

  Widget _openTripCard(Trip t) {
    const ink = Color(0xFF5A3300);
    Widget chip(IconData icon, String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: ink),
            const SizedBox(width: 5),
            Text(text,
                style: const TextStyle(
                    color: ink, fontWeight: FontWeight.w600, fontSize: 13)),
          ]),
        );

    return _HeroCard(
      key: const ValueKey('open'),
      gradient: Brand.sunGradient,
      shadow: const Color(0xFFFF9500),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const PulsingDot(color: Colors.white, size: 9),
            const SizedBox(width: 4),
            const Expanded(
              child: Text('TRIP IN PROGRESS',
                  style: TextStyle(
                      color: ink,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      fontSize: 12)),
            ),
            // Fix a wrong start mileage, purpose or destination
            TextButton.icon(
              onPressed: () => _open(EditTripScreen(trip: t)),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit'),
              style: TextButton.styleFrom(
                foregroundColor: ink,
                backgroundColor: Colors.white.withValues(alpha: 0.35),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Text('${t.vehicleRegNo}  →  ${t.destination}',
              style: const TextStyle(
                  color: ink, fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(t.purpose, style: TextStyle(color: ink.withValues(alpha: 0.8))),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            chip(Icons.timer_outlined, 'Out for ${durationText(t.duration)}'),
            chip(Icons.schedule, timeFmt.format(t.startTime)),
            chip(Icons.speed, km(t.startMileage)),
          ]),
          const SizedBox(height: 18),
          _CardButton(
            label: 'End trip',
            icon: Icons.flag_rounded,
            color: const Color(0xFFE07800),
            onPressed: () => _open(EndTripScreen(trip: t)),
          ),
        ],
      ),
    );
  }
}

/// Gradient card with a soft coloured shadow and a faint brand watermark.
class _HeroCard extends StatelessWidget {
  final Gradient gradient;
  final Color shadow;
  final Widget child;
  const _HeroCard(
      {super.key,
      required this.gradient,
      required this.shadow,
      required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: shadow.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 12)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        const Positioned(
          right: -30,
          bottom: -24,
          child: Opacity(
              opacity: 0.12, child: BrandMark(width: 190, animate: false)),
        ),
        Padding(padding: const EdgeInsets.all(20), child: child),
      ]),
    );
  }
}

/// White pill button used on the gradient cards.
class _CardButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  const _CardButton(
      {required this.label,
      required this.icon,
      required this.color,
      required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 26),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: color,
        minimumSize: const Size.fromHeight(54),
        elevation: 0,
      ),
    );
  }
}
