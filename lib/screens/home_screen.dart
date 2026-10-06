import 'package:flutter/material.dart';

import '../models.dart';
import '../services/db.dart';
import '../widgets/trip_widgets.dart';
import 'admin_trips_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_HomeData> _load() async {
    final results = await Future.wait(
        [Db.myProfile(), Db.myOpenTrip(), Db.myRecentTrips()]);
    return _HomeData(
        results[0] as Profile, results[1] as Trip?, results[2] as List<Trip>);
  }

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
            title: Text(
                data == null ? 'Trip Logbook' : 'Hi, ${data.profile.fullName}'),
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
                PopupMenuButton<String>(
                  onSelected: (v) => switch (v) {
                    'vehicles' => _open(const VehiclesScreen()),
                    'users' => _open(const UsersScreen()),
                    _ => Db.signOut(),
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'vehicles',
                      child: ListTile(
                          leading: Icon(Icons.directions_car_outlined),
                          title: Text('Vehicles')),
                    ),
                    PopupMenuItem(
                      value: 'users',
                      child: ListTile(
                          leading: Icon(Icons.people_outline),
                          title: Text('Drivers & users')),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'signout',
                      child: ListTile(
                          leading: Icon(Icons.logout),
                          title: Text('Sign out')),
                    ),
                  ],
                ),
              ] else
                IconButton(
                  tooltip: 'Sign out',
                  icon: const Icon(Icons.logout),
                  onPressed: Db.signOut,
                ),
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

  Widget _body(AsyncSnapshot<_HomeData> snap) {
    if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
      // Inside a ListView so pull-to-refresh still works while loading.
      return ListView(children: const [
        SizedBox(height: 160),
        Center(child: CircularProgressIndicator()),
      ]);
    }
    if (snap.hasError) {
      return ListView(children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            Text(Db.friendlyError(snap.error!), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _refresh, child: const Text('Retry')),
          ]),
        ),
      ]);
    }
    final d = snap.data!;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: d.openTrip == null ? _startCard() : _openTripCard(d.openTrip!),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('My recent trips',
              style: Theme.of(context).textTheme.titleMedium),
        ),
        if (d.recent.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No completed trips yet.')),
          ),
        ...d.recent.map((t) => TripTile(trip: t)),
      ],
    );
  }

  Widget _startCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          const Icon(Icons.route, size: 48),
          const SizedBox(height: 8),
          const Text('No trip in progress'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _open(const StartTripScreen()),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start a trip'),
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ]),
      ),
    );
  }

  Widget _openTripCard(Trip t) {
    return Card(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.directions_car, color: Colors.orange.shade800),
              const SizedBox(width: 8),
              Text('Trip in progress',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: Colors.orange.shade900)),
            ]),
            const SizedBox(height: 12),
            Text('${t.vehicleRegNo}  →  ${t.destination}',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(t.purpose),
            const SizedBox(height: 8),
            Text('Started ${dateTimeFmt.format(t.startTime)}'),
            Text('Start mileage: ${km(t.startMileage)}'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _open(EndTripScreen(trip: t)),
              icon: const Icon(Icons.flag),
              label: const Text('End trip'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: Colors.orange.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
