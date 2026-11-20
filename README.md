# American Corner Mombasa: Visitor Management

A Windows desktop app for the American Corner Mombasa front desk. It registers
visitors, checks them in and out, runs program rosters, keeps a full visit
history and produces the statistical reports needed for ECA reporting.

It works fully offline on a local database and syncs to the cloud when the
internet is available.

## Stack

| Area | Choice |
| --- | --- |
| App | Flutter Desktop (Windows), Dart |
| State | Riverpod 2 |
| Local database | SQLite through Drift (offline first) |
| Cloud | Supabase (database and auth) |
| PDF and printing | `pdf`, `printing` |
| Backend | None. There is no custom server of any kind |

Security rules the project follows:

- Only the Supabase **URL** and **anon key** are used. The service-role key is
  never used or stored in the app.
- Cloud access is limited by row-level security (see `supabase/schema.sql`).
- Staff passwords are hashed with PBKDF2-HMAC-SHA256 and are never synced.
- Five wrong sign-in attempts in a minute locks sign-in briefly.

## Features

- **Splash and sign-in:** local staff accounts. The first run creates the first
  admin account; admins can add more staff.
- **Dashboard:** live stats, quick find and check-in by name, member ID, phone or
  scanner, register new visitor (and check in), today's activities, recent
  check-ins, badge printing with a QR code.
- **Kiosk:** self check-in screen.
- **Visitors Directory:** searchable, filterable list; visitor profile with
  analytics; edit profile; print badge; check in or out; CSV export.
- **Visit History and Terminal Logs:** period filters, KPI cards, searchable log,
  session inspector, CSV export and a printable daily log sheet.
- **Programs and Activities:** daily schedule, pre-registration, roster, batch
  admit, walk-ins, capacity and room-clash checks, attendance sheet PDF, and a
  Create Program / Session dialog (F4).
- **Reports and Statistical Analytics:** monthly footfall against target, gender
  and youth ratios, pillar distribution, residence and age cohorts, CSV and PDF
  exports, and four report templates.
- **Cloud sync:** two-way, automatic every minute while signed in to the cloud
  account. Newer `updated_at` wins.

## Project layout

```
lib/
  main.dart
  core/
    config/       Supabase settings (from --dart-define)
    constants/    colours, spacing, text styles, strings
    data/         repositories (visitors, visits, programs, sessions,
                  directory, history, reports, settings, auth)
    database/     Drift tables and the generated code
    domain/       models and exceptions
    security/     password hashing
    services/     badge printing, CSV and PDF exports, app initialiser
    sync/         Supabase sync service and controller
    theme/        app theme
    utils/        date, phone, id and format helpers
    widgets/      shared widgets (cards, pills, avatars)
  features/
    auth/  splash/  kiosk/  shell/  dashboard/
    directory/  history/  programs/  reports/
supabase/
  schema.sql        base cloud tables and security rules
  migration_v2.sql  programs, rosters and demographics (run after schema.sql)
env.example.json
SETUP.md
```

Each feature keeps presentation (screens and widgets) separate from logic
(providers and repositories).

## Setup

1. **Install Flutter** and enable Windows desktop. Turn on **Developer Mode** in
   Windows (Settings, System, For developers).
2. **Install packages** in the project folder:

   ```
   flutter pub add flutter_riverpod:^2.6.1 drift drift_flutter crypto path_provider supabase_flutter pdf printing
   flutter pub add --dev drift_dev build_runner
   ```

3. **Generate the database code.** Run this once, and again every time
   `lib/core/database/tables.dart` changes:

   ```
   dart run build_runner build --delete-conflicting-outputs
   ```

4. **(Optional) set up Supabase** for cloud sync:
   1. Create a project at supabase.com.
   2. SQL Editor: run `supabase/schema.sql`, then `supabase/migration_v2.sql`.
   3. Authentication, Users, Add user (tick Auto Confirm). The terminals use
      this one account to sync.
   4. Project Settings, API: copy the Project URL and the anon / public key.
   5. Copy `env.example.json` to `env.json` and fill in the two values. Keep
      `env.json` out of Git.

   Without these values the app still works fully offline.

## Run

```
flutter run -d windows --dart-define-from-file=env.json
```

Without cloud sync you can leave out the define:

```
flutter run -d windows
```

On first launch, create the first admin account. After signing in, use the cloud
status chip at the top to sign in to the Supabase account and start syncing.

## Business rules

- A visitor is **inside** when their visit has no check-out and started today.
  Visits left open from earlier days are closed at 23:59 of their day when the
  app starts.
- Member IDs look like `ACM-YYYY-NNNN`. Phone numbers are stored in `+254...`
  form and must be unique.
- 16 workstations (`PC-01` to `PC-16`) are assigned automatically on request.
  Default hall capacity is 45.
- A visitor is **inactive** after 90 days without a visit.
- Programs recur as one-time, daily or weekly. Drafts are hidden from check-in.
  Walk-ins can be switched off per session, and full sessions refuse admission.
- Report figures for gender, age and residence only cover visitors whose details
  were recorded (with consent) at registration.
- The monthly footfall target defaults to 1,500.

## Data and exports

- The local database is a SQLite file managed by Drift on the terminal.
- Exports (CSV and PDF) are saved to
  `Documents/American Corner Mombasa/Exports`. CSV files open in Excel, with
  protection against spreadsheet formula injection.
- ECA reports contain aggregated statistics only, with no contact details.

## Changing the database

1. Edit `lib/core/database/tables.dart`.
2. Raise `schemaVersion` in `app_database.dart` and add a migration step in
   `onUpgrade`.
3. Add the matching columns in a new SQL file under `supabase/` and update
   `lib/core/sync/sync_service.dart`.
4. Run `dart run build_runner build --delete-conflicting-outputs`.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| Errors about a missing `Program`, `Visitor` or other getter | The generated code is stale. Delete `lib/core/database/app_database.g.dart`, then run build_runner again. |
| `build_runner` not found | Run the `flutter pub add --dev drift_dev build_runner` command above. |
| Windows plugin or symlink error | Turn on Developer Mode in Windows settings. |
| `sqlite3.dll` not found | Run `flutter pub add sqlite3_flutter_libs`. |
| Sync says it is not configured | Run with `--dart-define-from-file=env.json` and check both values. |
| "Cloud rejected the sync" | Run both SQL files in Supabase and make sure the sync user exists. |
| Analyzer shows old errors after fixes | VS Code: Ctrl+Shift+P, then "Dart: Restart Analysis Server". |

## Not built yet

- Quick Check-In, Register Visitor and Settings sidebar pages (the sidebar shows
  placeholders).
- Editing or cancelling a program after it is created.
- A settings screen for the monthly footfall target and hall capacity.
- Storing sub-county filters and a log-note editor in the history page.