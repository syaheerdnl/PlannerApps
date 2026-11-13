# Bayar

A personal finance planner for Android and iPhone that tells you **what to pay, and when**, and how much
of your salary is left in each envelope (fuel, food, and so on). *Bayar* means "pay" in Malay; amounts are in
ringgit (RM).

It works fully offline. Syncing the same data across your phones is optional and uses your own free
Supabase project.

## What it does

- **Bills and subscriptions.** Add a bill once (rent, phone, a streaming plan) with how often it repeats.
  Bayar lists what is overdue, what to pay now and what is coming, and lets you mark each one paid.
- **Reminders.** A notification at 9:00 local time the day before, on the pay-by date, on the due date and
  when something is overdue.
- **Scan a bill.** Photograph or pick a bill and Bayar fills in the name, amount and due date. The text is
  read on the phone, so the photo never leaves it and no API key is needed. You always review before saving.
- **Salary and envelopes.** Set your payday and salary, split it into envelopes, add spending in a few taps,
  and see how much is left in each, plus a safe amount to spend per day.
- **Swipe a bill right to delete it** (it asks you to confirm first).
- **Sync across devices** (optional). Your phones merge their changes; edits made offline are not lost.

Screens: **Home**, **Bills**, **Envelopes**, **Plan**.

## Run it

You need [Flutter](https://docs.flutter.dev/get-started/install) (developed with 3.44) and either an Android
device or emulator, or Xcode for iOS.

```bash
flutter pub get
flutter run
```

Debug builds start with a few demo bills and an example salary so the screens are not empty. Release builds
start empty.

To install a release build on an Android phone:

```bash
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

### Turn on sync (optional)

Create your own free Supabase project, run `supabase/migrations/001_bayar_sync.sql` in its SQL editor, and
build with the two values from your project. The full steps are in [supabase/README.md](supabase/README.md).

```bash
flutter run --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
            --dart-define=SUPABASE_ANON_KEY=YOUR-ANON-KEY
```

Use only the **anon** key. Never put the `service_role` key in the app.

## How it is built

Flutter with Provider for state, SQLite (sqflite) on the phone, and Supabase for the optional sync.

```
lib/
  core/        money, dates, theme            (money is always whole sen, never a double)
  domain/      pure logic: recurrence, pay cycles, budgets, reminder planning, bill-text parsing
  data/        SQLite database and repositories
  providers/   controllers the screens listen to
  sync/        sync engine, Supabase adapter, a no-op backend for offline use
  services/    notifications and the bill scanner (camera + on-device ML Kit)
  screens/     Home, Bills, Envelopes, Plan, forms
  widgets/     shared pieces such as the bill row and the floating tab bar
supabase/      SQL for the sync tables, plus a test that runs it in a real Postgres engine
tool/          helper scripts (icon generator, a fake Supabase server, a reminder test app)
test/          unit and widget tests
```

A few decisions worth knowing:

- **Money is stored as an integer number of sen** (RM 12.50 is `1250`), so totals add up exactly.
- **Nothing is hard-deleted.** Every table has `deleted_at`, `updated_at` and `synced_at`, which is what lets
  deletions and edits sync between phones.
- **Sync is pull-then-push with last-write-wins.** Each pull also re-reads the last 30 seconds, to cover rows
  that became visible just after their server timestamp.
- **Reminders are "inexact" alarms.** Android may deliver them a few minutes after 9:00. A reminder that is
  due but not yet delivered is never cancelled when the app re-plans (see `lib/services/reminder_diff.dart`).

## Tests

```bash
flutter analyze
flutter test
```

The suite has about 470 tests covering the recurrence and budget logic, the repositories and migrations,
the screens, the reminder planner, the bill-text parser and the sync engine (including a real Supabase client
run against a fake server: `dart run tool/fake_supabase.dart`).

The sync SQL can be run in a real Postgres engine without a Supabase account; see
[supabase/README.md](supabase/README.md).

### What has and has not been verified

Verified: the test suite; Android emulators and a real Android phone (reminders, scanning, install and
upgrade); the iPhone simulator; two phones syncing through the real Supabase client against a local fake
server; and the SQL in a real Postgres engine.

**Not yet verified:** sync against a live Supabase project, and a physical iPhone.

## Platform notes

**Android.** Notifications need the `POST_NOTIFICATIONS` permission on Android 13+; the app asks when you
turn reminders on. The release build needs the rules in `android/app/proguard-rules.pro` (ML Kit starts
itself by class name) and `android/app/src/main/res/raw/keep.xml` (the notification icon is found by name).

**iOS.** The bill scanner pulls Google ML Kit through Swift Package Manager.
- `xcodebuild` may ask for access to the keychain item for `github.com` once for each ML Kit package it
  downloads. If you do not want that, build with an empty temporary home folder, for example
  `HOME=/tmp/empty xcodebuild ...`.
- The app bundles `ios/Runner/LatinOCRResources.bundle` (the text model, which this package does not include
  itself) and links with `-ObjC` (in `ios/Flutter/*.xcconfig`). Without either, scanning crashes.

## Icons

`python3 tool/make_icons.py` redraws the app and notification icons for Android and iOS (needs Pillow).
