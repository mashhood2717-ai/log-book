import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import 'reminders.dart';

/// An error whose message is already fit to show a driver.
class AppException implements Exception {
  final String message;
  AppException(this.message);
  @override
  String toString() => message;
}

/// All backend calls live here so the screens stay simple.
class Db {
  static SupabaseClient get _c => Supabase.instance.client;

  static String get uid => _c.auth.currentUser!.id;

  // ---------------- Auth ----------------
  static Future<void> signIn(String email, String password) =>
      _c.auth.signInWithPassword(email: email.trim(), password: password);

  static Future<void> signOut() async {
    me = null;
    await Reminders.cancelAll(); // this phone should stop reminding
    await _c.auth.signOut();
  }

  /// The signed-in user's profile, cached by [myProfile].
  static Profile? me;
  static bool get isAdmin => me?.isAdmin ?? false;

  static Future<Profile> myProfile() async {
    final row =
        await _c.from('profiles').select().eq('id', uid).maybeSingle();
    if (row == null) {
      throw AppException(
          'Your account is not set up yet. Ask your admin to run the database setup.');
    }
    return me = Profile.fromMap(row);
  }

  // ---------------- Vehicles ----------------
  static Future<List<Vehicle>> vehicles({bool activeOnly = false}) async {
    var q = _c.from('vehicles').select();
    if (activeOnly) q = q.eq('active', true);
    final rows = await q.order('reg_no');
    return rows.map(Vehicle.fromMap).toList();
  }

  static Future<void> addVehicle(
          String regNo, String? description, int odometer) =>
      _c.from('vehicles').insert({
        'reg_no': regNo.trim().toUpperCase(),
        'description': description?.trim(),
        'last_odometer': odometer,
      });

  static Future<void> updateVehicle(int id, Map<String, dynamic> values) =>
      _c.from('vehicles').update(values).eq('id', id);

  // ---------------- Users (admin) ----------------
  // Creating/blocking logins needs the secret key, so these go through the
  // `admin-users` Edge Function (supabase/functions/admin-users), which checks
  // that the caller is an admin.
  static Future<dynamic> _adminUsers(Map<String, dynamic> body) async {
    final res = await _c.functions.invoke('admin-users', body: body);
    return res.data;
  }

  static Future<List<AppUser>> users() async {
    final data = await _adminUsers({'action': 'list'}) as List;
    final list = data
        .map((e) => AppUser.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList()
      ..sort((a, b) {
        if (a.banned != b.banned) return a.banned ? 1 : -1; // blocked last
        return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
      });
    return list;
  }

  static Future<void> createUser({
    required String email,
    required String password,
    required String fullName,
    String role = 'driver',
  }) =>
      _adminUsers({
        'action': 'create',
        'email': email.trim(),
        'password': password,
        'full_name': fullName.trim(),
        'role': role,
      });

  static Future<void> updateUser(String id,
          {String? fullName, String? role, String? password, bool? banned}) =>
      _adminUsers({
        'action': 'update',
        'id': id,
        if (fullName != null) 'full_name': fullName.trim(),
        if (role != null) 'role': role,
        if (password != null) 'password': password,
        if (banned != null) 'banned': banned,
      });

  static Future<void> deleteUser(String id) =>
      _adminUsers({'action': 'delete', 'id': id});

  // ---------------- Trips (driver) ----------------
  static Future<Trip?> myOpenTrip() async {
    final row = await _c
        .from('trips')
        .select(Trip.selectQuery)
        .eq('driver_id', uid)
        .eq('status', 'ongoing')
        .maybeSingle();
    return row == null ? null : Trip.fromMap(row);
  }

  static Future<List<Trip>> myRecentTrips({int limit = 30}) async {
    final rows = await _c
        .from('trips')
        .select(Trip.selectQuery)
        .eq('driver_id', uid)
        .eq('status', 'completed')
        .order('start_time', ascending: false)
        .limit(limit);
    return rows.map(Trip.fromMap).toList();
  }

  static Future<void> startTrip({
    required int vehicleId,
    required int startMileage,
    required String purpose,
    required String destination,
    GeoPoint? location,
  }) =>
      _c.from('trips').insert({
        'driver_id': uid,
        'vehicle_id': vehicleId,
        'start_mileage': startMileage,
        'purpose': purpose.trim(),
        'destination': destination.trim(),
        ...?location?.toColumns('start'),
      });

  static Future<void> endTrip({
    required int tripId,
    required int endMileage,
    double? fuelLitres,
    double? fuelCost,
    String? notes,
    GeoPoint? location,
  }) async {
    final rows = await _c
        .from('trips')
        .update({
          'status': 'completed',
          'end_mileage': endMileage,
          'fuel_litres': fuelLitres,
          'fuel_cost': fuelCost,
          'notes':
              (notes == null || notes.trim().isEmpty) ? null : notes.trim(),
          ...?location?.toColumns('end'),
        })
        .eq('id', tripId)
        .eq('status', 'ongoing')
        .select('id');
    // No row updated = trip was already ended (e.g. by admin or another phone)
    if (rows.isEmpty) {
      throw AppException('This trip had already been ended.');
    }
  }

  // ---------------- Editing / deleting trips ----------------
  /// How long after a trip ends it can still be corrected.
  /// Must match the `trips_update` policy in supabase/schema.sql.
  static const editWindow = Duration(hours: 24);

  /// Time left to correct a finished trip (null = open trip, no limit).
  static Duration? editTimeLeft(Trip t) =>
      t.endTime?.add(editWindow).difference(DateTime.now());

  /// The trip's driver or an admin may edit while it's open
  /// and for [editWindow] after it ends.
  static bool canEdit(Trip t) {
    if (!(isAdmin || t.driverId == uid)) return false;
    final left = editTimeLeft(t);
    return left == null || left > Duration.zero;
  }

  static Future<void> updateTrip(int id, Map<String, dynamic> values) async {
    final rows =
        await _c.from('trips').update(values).eq('id', id).select('id');
    if (rows.isEmpty) {
      throw AppException(
          'This trip can no longer be edited – the 24-hour limit has passed.');
    }
  }

  /// Admin only (enforced by the database).
  static Future<void> deleteTrip(int id) async {
    final rows = await _c.from('trips').delete().eq('id', id).select('id');
    if (rows.isEmpty) {
      throw AppException('Trip not deleted – it may already be gone.');
    }
  }

  // ---------------- Trips (admin) ----------------
  /// Every trip currently out, for the fleet status board.
  static Future<List<Trip>> openTrips() async {
    final rows = await _c
        .from('trips')
        .select(Trip.selectQuery)
        .eq('status', 'ongoing')
        .order('start_time');
    return rows.map(Trip.fromMap).toList();
  }

  static Future<List<Trip>> allTrips({
    required DateTime from,
    required DateTime to,
    int? vehicleId,
  }) async {
    // Supabase caps each response (1000 rows by default), so fetch in pages.
    const page = 1000;
    final trips = <Trip>[];
    while (true) {
      var q = _c
          .from('trips')
          .select(Trip.selectQuery)
          .gte('start_time', from.toUtc().toIso8601String())
          .lt('start_time', to.toUtc().toIso8601String());
      if (vehicleId != null) q = q.eq('vehicle_id', vehicleId);
      final rows = await q
          .order('start_time', ascending: false)
          .order('id', ascending: false)
          .range(trips.length, trips.length + page - 1);
      trips.addAll(rows.map(Trip.fromMap));
      if (rows.length < page) return trips;
    }
  }

  /// Turns backend errors into messages a driver can understand.
  static String friendlyError(Object e) {
    if (e is AppException) return e.message;
    if (e is TimeoutException) {
      return 'The server did not answer in time. Check your internet and tap Retry.';
    }
    if (e is SocketException || e is HandshakeException) {
      return 'Cannot reach the server. Check your internet connection.\n($e)';
    }
    if (e is AuthException) return e.message;
    if (e is FunctionException) {
      final d = e.details;
      if (d is Map && d['error'] is String) return d['error'] as String;
      if (e.status == 404) {
        return 'User management is not set up yet (admin-users function missing).';
      }
      if (e.status == 401) return 'Please sign out and sign in again.';
      return 'Server error (${e.status}). Try again.';
    }
    if (e is PostgrestException) {
      if (e.code == '23505') {
        if (e.message.contains('one_open_trip_per_vehicle')) {
          return 'This vehicle is already on an open trip.';
        }
        if (e.message.contains('one_open_trip_per_driver')) {
          return 'You already have an open trip. End it first.';
        }
        return 'This record already exists.';
      }
      if (e.code == '23514') {
        if (e.message.contains('end_not_below_start')) {
          return 'End mileage cannot be less than start mileage.';
        }
        return 'Some values are not valid. Check the numbers and try again.';
      }
      if (e.code == '22003') return 'A number entered is too large.';
      if (e.code == '42501') return 'You do not have permission to do this.';
      if (e.code == 'P0001') return e.message; // raised by our own triggers
      return e.message;
    }
    return e.toString();
  }
}
