double? _toDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

DateTime? _toDate(dynamic v) =>
    v == null ? null : DateTime.parse(v.toString()).toLocal();

/// A GPS reading taken by the driver's phone.
class GeoPoint {
  final double lat;
  final double lng;
  final double? accuracy; // metres

  const GeoPoint(this.lat, this.lng, {this.accuracy});

  static GeoPoint? fromColumns(Map<String, dynamic> m, String prefix) {
    final lat = _toDouble(m['${prefix}_lat']);
    final lng = _toDouble(m['${prefix}_lng']);
    if (lat == null || lng == null) return null;
    return GeoPoint(lat, lng, accuracy: _toDouble(m['${prefix}_accuracy']));
  }

  Map<String, dynamic> toColumns(String prefix) => {
        '${prefix}_lat': lat,
        '${prefix}_lng': lng,
        '${prefix}_accuracy': accuracy,
      };

  /// Opens in the Google Maps app or browser – no API key needed.
  Uri get mapsUrl =>
      Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');

  @override
  String toString() =>
      '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
}

class Profile {
  final String id;
  final String fullName;
  final String role;

  Profile({required this.id, required this.fullName, required this.role});

  bool get isAdmin => role == 'admin';

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: m['id'] as String,
        fullName: (m['full_name'] ?? '') as String,
        role: (m['role'] ?? 'driver') as String,
      );
}

/// A login account, as seen by an admin on the Drivers screen.
class AppUser {
  final String id;
  final String email;
  final String fullName;
  final String role;
  final bool banned;
  final DateTime? lastSignIn;

  AppUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.banned,
    this.lastSignIn,
  });

  bool get isAdmin => role == 'admin';
  String get displayName => fullName.isEmpty ? email : fullName;

  factory AppUser.fromMap(Map<String, dynamic> m) => AppUser(
        id: m['id'] as String,
        email: (m['email'] ?? '') as String,
        fullName: (m['full_name'] ?? '') as String,
        role: (m['role'] ?? 'driver') as String,
        banned: (m['banned'] ?? false) as bool,
        lastSignIn: _toDate(m['last_sign_in_at']),
      );
}

class Vehicle {
  final int id;
  final String regNo;
  final String? description;
  final int lastOdometer;
  final bool active;

  Vehicle({
    required this.id,
    required this.regNo,
    this.description,
    required this.lastOdometer,
    required this.active,
  });

  String get label => (description == null || description!.isEmpty)
      ? regNo
      : '$regNo – $description';

  factory Vehicle.fromMap(Map<String, dynamic> m) => Vehicle(
        id: _toInt(m['id'])!,
        regNo: m['reg_no'] as String,
        description: m['description'] as String?,
        lastOdometer: _toInt(m['last_odometer']) ?? 0,
        active: (m['active'] ?? true) as bool,
      );
}

class Trip {
  final int id;
  final String driverId;
  final String driverName;
  final int vehicleId;
  final String vehicleRegNo;
  final String status;
  final DateTime startTime;
  final int startMileage;
  final String purpose;
  final String destination;
  final DateTime? endTime;
  final int? endMileage;
  final int? distanceKm;
  final double? fuelLitres;
  final double? fuelCost;
  final String? notes;
  final GeoPoint? startLocation;
  final GeoPoint? endLocation;

  Trip({
    required this.id,
    required this.driverId,
    required this.driverName,
    required this.vehicleId,
    required this.vehicleRegNo,
    required this.status,
    required this.startTime,
    required this.startMileage,
    required this.purpose,
    required this.destination,
    this.endTime,
    this.endMileage,
    this.distanceKm,
    this.fuelLitres,
    this.fuelCost,
    this.notes,
    this.startLocation,
    this.endLocation,
  });

  bool get isOngoing => status == 'ongoing';

  /// Time out of base – up to now for an open trip.
  Duration get duration => (endTime ?? DateTime.now()).difference(startTime);

  /// Select string that pulls the vehicle reg no and driver name with each trip.
  static const selectQuery = '*, vehicles(reg_no), profiles(full_name)';

  factory Trip.fromMap(Map<String, dynamic> m) {
    final v = m['vehicles'] as Map<String, dynamic>?;
    final p = m['profiles'] as Map<String, dynamic>?;
    return Trip(
      id: _toInt(m['id'])!,
      driverId: m['driver_id'] as String,
      driverName: (p?['full_name'] ?? '') as String,
      vehicleId: _toInt(m['vehicle_id'])!,
      vehicleRegNo: (v?['reg_no'] ?? '') as String,
      status: m['status'] as String,
      startTime: _toDate(m['start_time'])!,
      startMileage: _toInt(m['start_mileage'])!,
      purpose: (m['purpose'] ?? '') as String,
      destination: (m['destination'] ?? '') as String,
      endTime: _toDate(m['end_time']),
      endMileage: _toInt(m['end_mileage']),
      distanceKm: _toInt(m['distance_km']),
      fuelLitres: _toDouble(m['fuel_litres']),
      fuelCost: _toDouble(m['fuel_cost']),
      notes: m['notes'] as String?,
      startLocation: GeoPoint.fromColumns(m, 'start'),
      endLocation: GeoPoint.fromColumns(m, 'end'),
    );
  }
}
