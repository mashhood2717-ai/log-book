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

## Trip reminders

- Every signed-in phone gets a notification **Monday–Friday every hour from 9 AM to 6 PM, and Saturday–Sunday at 11 AM and 5 PM (Pakistan time)** (whatever time zone the phone is set to): a reminder to start a trip before leaving, and to check every trip is logged. If a trip is still open, the reminder says so.
- To change the times, edit `officeStart`, `officeEnd` and `weekendHours` in `lib/services/reminders.dart` (54 weekly reminders today; iPhone allows at most 64).
- Scheduled on the phone itself (`lib/services/reminders.dart`, flutter_local_notifications) – no server; they keep working after a restart. Turn off / send a test under **⋮ → Reminders**. Signing out stops them.
- Android uses exact alarms (`USE_EXACT_ALARM`), fine for a sideloaded APK; a Play Store release would need to justify that permission or fall back to inexact delivery (already handled in code).

## Live location & routes

While a trip is open the driver's phone records a GPS point about once a minute; admins see it live.
- **Fleet status → map icon**: every vehicle that's out, where it is now (grey = not heard from for 15+ min). Refreshes every 30 s.
- **Trip details → View route**: the route on a map, GPS distance vs odometer (flagged if they differ >15 % and >3 km), and gaps with no location.
- Maps: OpenStreetMap via flutter_map (no API key).

How it works: `lib/services/location_tracker.dart`. On **Android** it runs in a separate foreground service (flutter_foreground_task, "Trip in progress" notification) that keeps going with the screen off and **even if the app is swiped away**. On **iPhone** it uses background location (blue indicator) while the app is in memory. Points are queued on the phone when offline. Uploads go through the `add_trip_points` database function using the trip's secret `tracking_key` (no login needed, only for that trip, only while open + 30 min), so the background service never touches the driver's session. Points: table `trip_points`; latest position: view `trip_last_point`.

Drivers must have **v1.7.0+** for their routes to be recorded.

## Driver trip alerts (admins, Android)

Admins get a push notification when a driver **starts** ("🚗 Ali Khan left with LEB-1234 → Nowshera…") or **ends** a trip ("✅ Ali Khan is back – LEB-1234: 88 km · 3h 05m · fuel…"). Not for their own trips. On/off: **⋮ → Reminders → Driver trip alerts**.

How it works: the admin's phone saves its Firebase token in `device_tokens` → the `trips_notify_admins` trigger (schema.sql, via pg_net) calls the `trip-alerts` Edge Function → it re-reads the trip, records the alert once in `trip_alerts`, and sends it through Firebase Cloud Messaging.

Setup (once):
1. Firebase console → create a project → add an **Android app** with package `com.weatherwalay.trip_logbook` → download `google-services.json` and copy its four values into `lib/config.dart` (`firebase*`).
2. Firebase → Project settings → **Service accounts** → *Generate new private key*. Paste the whole JSON as the Supabase Edge Function secret `FCM_SERVICE_ACCOUNT`. Never commit it.
3. Deploy `supabase/functions/trip-alerts/index.ts` as function `trip-alerts` with **Verify JWT off** (the function checks everything itself and sends each alert at most once).
4. Run `supabase/schema.sql` again.

iPhone: push needs a paid Apple Developer account (APNs), so alerts are Android-only for now.

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
deno test -A --node-modules-dir=none supabase/functions/trip-alerts/  # alert wording + Google auth signing
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
