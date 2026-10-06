# Trip Logbook – Owner's Guide

Where everything is stored, how to look after it, and what to do when something goes wrong.

_Last updated: 6 October 2026_

---

## 1. Where everything lives (summary)

| What | Where | Backed up? |
|---|---|---|
| **All trip, vehicle and driver data** | Supabase (cloud database), Mumbai region | ❌ Not automatically on the free plan – see [§5](#5-backups) |
| **Login accounts and passwords** | Supabase → Authentication | Stored with the database |
| **App source code** | This computer: `D:\trip_logbook` | ❌ Only on this computer – back it up |
| **App signing key** (needed to publish updates) | `D:\trip_logbook\android\app\upload-keystore.jks` + `D:\trip_logbook\android\key.properties` | ⚠️ You must keep your own copy |
| **Logo files** (SVG + PNG, for print/web) | `D:\trip_logbook\branding\` | In git |
| **The installable app (APK)** | `D:\trip_logbook\build\app\outputs\flutter-apk\app-release.apk` | Can be rebuilt any time from the code |
| **Drivers' phones** | Only the login session – **no trip data is kept on phones** | Nothing to back up |

If a phone is lost, broken or replaced, **no data is lost**. Install the app again and sign in.

---

## 2. The Supabase backend

| | |
|---|---|
| Dashboard | https://supabase.com/dashboard/project/ofvpqdqnvmgdnyyjgevi |
| Project URL | `https://ofvpqdqnvmgdnyyjgevi.supabase.co` |
| Project ID | `ofvpqdqnvmgdnyyjgevi` |
| Region | South Asia (Mumbai) |
| Plan | Free |
| Supabase login | The account you signed up to supabase.com with |
| Admin user in the app | mashhood.iqbal@weatherwalay.com |

### Keys

| Key | Where it is | Safe to share? |
|---|---|---|
| **Publishable key** (`sb_publishable_…`) | Inside the app: `lib/config.dart` | Yes – it is designed to be in the app. The database rules decide what each user can see. |
| **Secret / service_role key** | Supabase → Project Settings → API Keys | ❌ **Never.** It bypasses all security. Never put it in the app or send it to anyone. |
| **Database password** | Chosen when the project was created | ❌ Keep private. Not used by the app. |

### What is stored (tables)

Open **Supabase → Table Editor** to see and edit any of these.

**`profiles`** – one row per person who can sign in
- `full_name` – shown in the app and the CSV export
- `role` – `driver` or `admin`

**`vehicles`**
- `reg_no`, `description` (make/model)
- `last_odometer` – updated automatically when a trip ends
- `active` – turned off = drivers can't pick it any more (history is kept)

**`trips`** – one row per trip
- who: `driver_id`, `vehicle_id`
- start: `start_time`, `start_mileage`, `purpose`, `destination`, `start_lat` / `start_lng` (GPS)
- end: `end_time`, `end_mileage`, `fuel_litres`, `fuel_cost`, `notes`, `end_lat` / `end_lng` (GPS)
- `distance_km` – calculated by the database
- `status` – `ongoing` (vehicle is out) or `completed`

**Authentication → Users** – emails and passwords. Passwords are stored encrypted (hashed) by Supabase; nobody, including you, can read them.

The full database design and security rules are in `supabase/schema.sql`.

### Security rules (enforced by the database, not just the app)

- Drivers see and edit **only their own** trips, and only while the trip is open.
- Admins see everything.
- Start and end times come from the **server clock** – drivers can't change them.
- A vehicle can only be on one open trip; a driver can only have one open trip.
- Only admins can add or change vehicles and change roles.

---

## 3. Free plan limits

| Limit | What it means for you |
|---|---|
| 500 MB database | Years of trips for a small fleet. Not a concern. |
| **Project pauses after 7 days with no activity** | If nobody uses the app for a week, it stops working. Fix: open the dashboard and click **Restore project**. **No data is lost.** Daily use prevents this. |
| No automatic backups | You must export data yourself – see below. |

Upgrading to **Pro ($25/month)** removes the pause and adds daily automatic backups. Supabase → Organization → Billing.

---

## 4. Everyday tasks

All user tasks are done **in the app**: sign in as admin → **⋮ menu → Drivers & users**.

### Add a new driver
1. **Add driver** → enter name and email (any address – it doesn't need a real inbox). A password is filled in for you.
2. Tap **Add** → **Share** to send the login details on WhatsApp.
3. Send them the APK file too.

### Driver forgot their password
Tap the driver → **Reset password** → **Save** → **Share** the new one.

### Make someone an admin
Tap the person → **Make admin**. (You can't remove your own admin rights, so you can never lock yourself out.)

### A driver leaves
Tap the driver → **Block**. They can no longer sign in, and their trips stay in the records. (It can take up to an hour before a phone that is already signed in is logged out.)
**Delete** only works for people with no trips – e.g. an account created by mistake.

> Behind the scenes this uses the `admin-users` Edge Function (see [§6](#6-the-app-and-its-code)). The same tasks can still be done by hand in the Supabase dashboard (Authentication → Users, Table Editor → profiles) if ever needed.

### Add / retire a vehicle
In the app, as admin: **car icon** → **Add vehicle**, or tap a vehicle to edit it. Use the switch to make a sold or retired vehicle inactive (its history stays).

### Correct a wrong trip entry
In the app, tap the trip → **Edit trip**. The driver (or an admin) can correct mileage, purpose, destination, fuel and notes:
- while the trip is open, and
- for **24 hours after it ends**. After that it's locked.

Start/end times and GPS locations can't be changed. A corrected trip shows an **EDITED** label with the time of the change, so you always know.
The vehicle's odometer is fixed automatically when the end mileage is corrected.

Older than 24 hours? Admins can still correct it in **Supabase → Table Editor → trips** (double-click the value).

### Delete a trip (admin)
Tap the trip → **Delete** → confirm. It is removed permanently. If it was the vehicle's latest trip, the vehicle's odometer goes back to the previous reading.

### A driver forgot to end a trip
Best: ask the driver to open the app and tap **End trip** with the real odometer reading.
If that's not possible: in **Table Editor → trips** set `end_mileage`, then `status` = `completed`.
If the trip was started by mistake, you can **Delete** it in the app instead.

---

## 5. Backups

There are **no automatic backups on the free plan**. Do this **at the start of every month**:

1. **Monthly trip report** – in the app as admin: **table icon** → choose last month → **download icon** → save the CSV to Google Drive.
2. **Full copy of each table** – Supabase → **Table Editor** → open `trips`, `vehicles`, `profiles` in turn → **Export → Export as CSV**. Save all three to Google Drive.

Keep these in one Drive folder, e.g. `Trip Logbook Backups/2026-10`.

---

## 6. The app and its code

| | |
|---|---|
| Code folder | `D:\trip_logbook` |
| Built with | Flutter (Dart) + Supabase |
| App ID | `com.weatherwalay.trip_logbook` |
| Current version | see `version:` in `pubspec.yaml` |
| Distributed as | APK file, installed by hand (not on the Play Store) |

⚠️ **The code folder is not backed up and is not in git.** If this computer dies, the code is gone (the data in Supabase is safe). Back it up by either:
- zipping `D:\trip_logbook` (you can skip the `build` and `.dart_tool` folders) to Google Drive after each change, or
- putting it in a private GitHub repository.

### Signing key – keep it safe

Every update of the app must be signed with the same key, or drivers' phones will refuse to install it.

| File | Location |
|---|---|
| Key | `D:\trip_logbook\android\app\upload-keystore.jks` |
| Its password | `D:\trip_logbook\android\key.properties` |

- Keep a copy of **both files** somewhere other than this computer (private Drive folder or USB stick).
- Don't send them on WhatsApp or email, and don't share them. Anyone with them can make a fake "update" of your app.
- On a new computer, copy them back to the same locations.

### The `admin-users` Edge Function

Adding/blocking users needs the Supabase secret key, which must never be in the app. So that part runs on Supabase's servers:

| | |
|---|---|
| Code | `supabase/functions/admin-users/index.ts` |
| Where it runs | Supabase → **Edge Functions → admin-users** |
| Security | Rejects anyone who is not signed in as an admin |

If you change the code, paste the new version in Supabase → Edge Functions → admin-users → **Code** → **Deploy**.

### Releasing an update

1. Raise the version in `pubspec.yaml`, e.g. `1.0.0+1` → `1.0.1+2` (the number after `+` must always go up)
2. In a terminal in `D:\trip_logbook`: `flutter build apk --release`
3. Send `build\app\outputs\flutter-apk\app-release.apk` to drivers – they tap it and choose **Update**. Their login is kept.

If the database design changed, also run the new `supabase/schema.sql` in **Supabase → SQL Editor** first. It is safe to run again; it only adds what is missing.

---

## 7. If something goes wrong

| Problem | What to do |
|---|---|
| App says it can't connect / nothing loads for everyone | Open the Supabase dashboard. If the project is **paused**, click **Restore project**. |
| One driver can't sign in | In the app: **⋮ → Drivers & users** – are they **Blocked**? Is the email right? Reset their password if needed. |
| Drivers & users screen says "not set up yet" | The `admin-users` Edge Function isn't deployed – see §6. |
| Signed in but "account is not set up" | Their row is missing in `profiles`. Re-run `supabase/schema.sql` – it creates missing profiles. |
| "Location not recorded" on trips | Phone's location was off or permission denied. Phone **Settings → Apps → Trip Logbook → Permissions → Location → Allow**. |
| Update won't install ("App not installed") | The APK was signed with a different key. Restore the signing key files from backup and rebuild. Never generate a new key unless the old one is truly lost – then every driver must uninstall and reinstall. |
| Computer lost or broken | Data is safe in Supabase. Restore the code and signing key from your backups. |
| Supabase account lost | Recover it at supabase.com with the email you signed up with. Keep that email account secure – it controls all the data. |

---

## 8. Related files

- `README.md` – technical setup for a developer
- `supabase/schema.sql` – database design and security rules
- `lib/config.dart` – Supabase URL and publishable key used by the app
- `supabase/functions/admin-users/index.ts` – server code for managing users
