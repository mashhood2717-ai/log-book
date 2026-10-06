# Trip Logbook (Flutter + Supabase)

> **Owner / admin?** See [OWNER_GUIDE.md](OWNER_GUIDE.md) for where your data is stored, backups, everyday tasks and what to do when something goes wrong.

Drivers sign in, **start a trip** (vehicle, start mileage, purpose, destination) and, on return, **end the trip** (end mileage, fuel litres/cost, remarks). The phone's GPS position is stamped at start and end.

Admins get:
- **Fleet status** – which vehicles are out right now, with which driver, where to, since when, and where they left from. Available vehicles are listed below.
- **All trips** – every trip by month with totals (km, fuel, cost), filter by vehicle, CSV export.
- **Vehicles** – add/edit/deactivate vehicles.
- **Drivers & users** – add drivers, reset passwords, block/unblock, make admin (via the `admin-users` Edge Function).

## What's inside

```
lib/
  main.dart                 app start + login/home switch
  config.dart               <-- paste your Supabase URL + key here
  models.dart               Profile, Vehicle, Trip
  services/db.dart          all backend calls
  services/location.dart    reads the phone's GPS (no API key)
  screens/
    login_screen.dart
    home_screen.dart        open-trip card / start button / my trips
    start_trip_screen.dart
    end_trip_screen.dart
    fleet_screen.dart       who has which vehicle right now (admin)
    admin_trips_screen.dart month view, totals, CSV export (admin)
    vehicles_screen.dart    add/edit/deactivate vehicles (admin)
    users_screen.dart       add/block drivers, reset passwords (admin)
  widgets/trip_widgets.dart trip list tile + detail sheet, map links
  widgets/location_capture.dart  GPS status line on start/end forms
supabase/schema.sql         database, security rules, triggers
supabase/functions/admin-users/index.ts   server-side user management
```

## 1. Backend setup (Supabase, ~10 min)

1. Create a free project at https://supabase.com (choose the **Mumbai / ap-south-1** region for lower latency from Pakistan).
2. **SQL Editor > New query** → paste all of `supabase/schema.sql` → **Run**.
   It is safe to run again later (e.g. after updating the app) – it only adds what's missing.
3. **Authentication > Sign In / Providers**: turn **off** "Allow new users to sign up" (only admin creates accounts).
4. **Authentication > Users > Add user > Create new user** for yourself and each driver (tick *Auto Confirm User*).
5. Make yourself admin (SQL Editor, change the email):
   ```sql
   update public.profiles set role = 'admin'
   where id = (select id from auth.users where email = 'you@weatherwalay.com');
   ```
6. **Table Editor > profiles** → set each driver's `full_name`.
7. **Project Settings > API Keys** → copy the Project URL and the **publishable** key (or legacy *anon public* key) into `lib/config.dart`. Never put the secret/service_role key in the app.

8. **Edge Functions → Deploy a new function → Via Editor** → name it `admin-users` → paste `supabase/functions/admin-users/index.ts` → in the function's settings turn **off** "Verify JWT with legacy secret" (the function checks the caller itself) → **Deploy**. This powers the Drivers & users screen.

## 2. Run the app

```bash
flutter pub get
flutter run                 # phone connected via USB, or emulator
flutter build apk --release # APK to share with drivers: build/app/outputs/flutter-apk/app-release.apk
```

Sign in as admin → tap the car icon → **Add vehicle** (reg no, model, current odometer). Drivers can now log trips.

## GPS / location

- The app records the phone's position **once at trip start and once at trip end** – there is no background tracking, so no battery drain.
- It uses the phone's own GPS. **No Google API key or billing account is needed.** "View on map" opens Google Maps through a normal link.
- The driver is asked for location permission the first time. If GPS is off or there is no fix (e.g. indoors), the driver can retry or continue; the trip then shows **"Not captured"** for you, so you can follow up.
- In the CSV export, start/end locations are Google Maps links.

## Rules enforced by the backend (not just the app)

- A driver sees and edits **only their own** trips; admin sees everything.
- A trip can be edited only while it's **open**; once ended it's locked (admin can still correct it in Table Editor).
- One open trip per driver and per vehicle.
- End mileage can't be less than start mileage; distance is calculated by the database.
- Start/end times come from the **server clock** — drivers can't back-date or forward-date either.
- Trips can't be started on a vehicle marked inactive.
- Each vehicle's `last_odometer` updates automatically when a trip ends, and pre-fills the next driver's start mileage. The app warns if a start reading is below it, or more than 50 km above it (possible unlogged use).
- Only admins can add/edit vehicles or change roles.

## Removing a driver

Don't delete a driver who has trips (Supabase will refuse, because their trips reference them). Instead, in **Authentication > Users** open the user and **Ban** them, which blocks sign-in and keeps their history.

## Common tweaks

- Currency label: `AppConfig.currency` in `lib/config.dart`.
- Gap warning (50 km): `start_trip_screen.dart`.
- Theme colour: `colorSchemeSeed` in `main.dart`.
- App icon: add `flutter_launcher_icons` if you want the WeatherWalay logo.
