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
    edit_trip_screen.dart   correct a trip (open, or up to 24 h after it ends)
    fleet_screen.dart       who has which vehicle right now (admin)
    admin_trips_screen.dart month view, totals, CSV export (admin)
    vehicles_screen.dart    add/edit/deactivate vehicles (admin)
    users_screen.dart       add/block drivers, reset passwords (admin)
  widgets/trip_widgets.dart trip list tile + detail sheet, map links
  widgets/location_capture.dart  GPS status line on start/end forms
  widgets/brand.dart        WeatherWalay colours, animated logo mark, wordmark, loader
  widgets/animations.dart   fade/slide-in, pulsing dot, count-up, drifting background
branding/                   logo files (SVG/PNG) and app-icon sources
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

## iPhone (Codemagic + Sideloadly)

iPhone apps can only be built on a Mac, so the iPhone version is built in the cloud by **Codemagic** using `codemagic.yaml`.

**Build** (codemagic.io, free Mac build minutes each month):
1. Sign in with GitHub → **Add application** → choose the `log-book` repository (Flutter App).
2. Codemagic finds `codemagic.yaml` → workflow **iOS for Sideloadly** → **Start new build** → branch `main`.
3. After ~10–15 minutes, open the build → **Artifacts** → download `TripLogbook-x.y.z-unsigned.ipa`.

Pushing to `main` starts a new build automatically.

**Install** (Windows PC + iPhone with a cable):
1. Install **iTunes** (from apple.com, not the Microsoft Store version) and **Sideloadly** (sideloadly.io).
2. Connect the iPhone, tap **Trust** on the phone.
3. Sideloadly: drag in the `.ipa`, enter your Apple ID, click **Start**.
4. On the iPhone: **Settings → General → VPN & Device Management** → your Apple ID → **Trust**. On iOS 16+ also turn on **Settings → Privacy & Security → Developer Mode** (the phone restarts).

**Limits of a free Apple ID:** the app stops opening after **7 days** – reinstall with Sideloadly (your trips are safe on the server; just sign in again if asked). Max 3 sideloaded apps per phone. A paid Apple Developer account ($99/year) extends this to 1 year and allows TestFlight, which is much easier for giving the app to several iPhone drivers.

## Rules enforced by the backend (not just the app)

- A driver sees and edits **only their own** trips; admin sees everything.
- A driver can edit their trip while it's **open** and for **24 hours after it ends**; then it's locked. Times, GPS points, vehicle and driver can never be changed by drivers. Corrected trips are marked **Edited**.
- Only admins can **delete** trips. Deleting or correcting a trip fixes the vehicle's odometer automatically.
- One open trip per driver and per vehicle.
- End mileage can't be less than start mileage; distance is calculated by the database.
- Start/end times come from the **server clock** — drivers can't back-date or forward-date either.
- Trips can't be started on a vehicle marked inactive.
- Each vehicle's `last_odometer` updates automatically when a trip ends, and pre-fills the next driver's start mileage. The app warns if a start reading is below it, or more than 50 km above it (possible unlogged use).
- Only admins can add/edit vehicles or change roles.

## Removing a driver

Don't delete a driver who has trips (Supabase will refuse, because their trips reference them). Instead, in **Authentication > Users** open the user and **Ban** them, which blocks sign-in and keeps their history.

## Testing

```bash
flutter test                                                   # app
deno run -A --node-modules-dir=none supabase/tests/schema_test.ts  # database rules on a real Postgres
```

## Branding

- The WeatherWalay mark is drawn in code (`lib/widgets/brand.dart`), so it is sharp at any size and animates: the drops fall in and the sun pops up; while loading, the drops bob.
- Logo files for print/web are in `branding/` – `weatherwalay_deployment_logo.svg/.png` (transparent and white background) and `weatherwalay_mark.svg/.png`.
- App icon sources are in `branding/icon/`. After changing them run `dart run flutter_launcher_icons`.

## Common tweaks

- Currency label: `AppConfig.currency` in `lib/config.dart`.
- Gap warning (50 km): `start_trip_screen.dart`.
- Brand colours: `Brand` in `lib/widgets/brand.dart`; light/dark colour sets: `AppColors` (same file) – use `context.colors.ink` etc., never fixed colours; app theme: `appTheme()` in `main.dart`.
- Dark mode follows the phone by default; users can pick System / Light / Dark under **⋮ → Appearance** (saved on the device by `lib/services/theme_settings.dart`).
