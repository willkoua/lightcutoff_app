# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Dependencies
flutter pub get
cd ios && pod install && cd ..   # iOS only

# Static analysis & formatting (both must pass before commit)
flutter analyze                  # must output "No issues found"
dart format .                    # auto-format; use --set-exit-if-changed in CI

# Tests
flutter test                     # all unit + widget tests
flutter test test/widget_test.dart   # single file

# Generate localizations (after editing ARB files)
flutter gen-l10n

# Run on a connected device — 3 environments via APP_ENV (dev | staging | prod)
flutter run --dart-define=APP_ENV=dev            # local Firebase emulators + dev tools
flutter run --dart-define=APP_ENV=staging        # online lightcutoff-dev + dev tools
flutter run --dart-define=APP_ENV=prod           # prod project (NOT CREATED YET → throws)
flutter run                                      # default = staging (legacy behavior)
flutter run --dart-define=USE_EMULATOR=true      # legacy alias for APP_ENV=dev
flutter run --dart-define=APP_ENV=dev \
            --dart-define=EMULATOR_HOST=192.168.x.x  # physical device vs emulators

# Build (always pass APP_ENV explicitly for release artifacts)
flutter build apk --release --dart-define=APP_ENV=staging
flutter build appbundle --release --dart-define=APP_ENV=staging
flutter build ipa --release --dart-define=APP_ENV=staging

# Firebase emulators (Auth 9099, Firestore 8080, RTDB 9000, Storage 9199)
firebase emulators:start
firebase emulators:start --import=./emulator-data --export-on-exit=./emulator-data
```

## Architecture

The app follows a strict **4-layer architecture**:

```
UI (screens / widgets / providers)
   ↓ depends on interfaces only
Repository (lib/repositories/)        ← abstract contracts
   ↓ implemented by
Service (lib/services/)               ← concrete Firebase / OS code
   ↓ wraps
Firebase SDK / OS APIs
```

Providers hold `ChangeNotifier` state and call repository interfaces — never services directly. This means tests mock the repository, not Firebase.

### Navigation flow

```
NjukaApp (MultiProvider: AuthProvider + LocaleProvider + ConnectivityProvider + RegionProvider)
  └─ OnboardingGate          checks SharedPrefs "onboarding_seen"
       ├─ OnboardingScreen   first launch only
       └─ AuthGate           listens to AuthProvider.status (6 states since 2026-06-24)
            ├─ SplashScreen           (unknown)
            ├─ MainShell              (anonymous)     — Firebase Anonymous Auth, profile wall
            ├─ MainShell              (authenticated) — full profile
            ├─ EmailVerificationScreen (awaitingVerification)  — post-register or post-upgrade
            ├─ CompleteProfileScreen  (profileIncomplete)      — post first social sign-in
            └─ AnonymousRetryScreen   (unauthenticated)        — signInAnonymously failed
                 └─ MainShell tabs : HomeScreen / MapScreen / ProfileScreen
```

`MainShell` is also where FCM push tap → `ReportDetailScreen` navigation happens via `NotificationService.pendingReportId` (a `ValueNotifier`). Direct navigation with `navigatorKey` is avoided because `ReportProvider` is scoped under `AuthGate`.

### Anonymous auth (pivot 2026-06-24)

`AuthProvider._onAuthStateChanged(null)` triggers `signInAnonymously()` once per provider lifetime (anti-loop flag). The resulting anonymous user reaches `AuthStatus.anonymous` and is allowed to **read, signal, and vote** — Firestore rules require only `request.auth != null`. Social features (profile, stats, follow quartier, FCM) are gated by `!isAnonymous()` rules (firestore.rules helper `isAnonymous() = sign_in_provider == 'anonymous'`). Upgrade flow:

- `ProfileScreen` shows `_UpgradeWall` when `auth.isAnonymous` → `UpgradeAccountScreen` (full form).
- `auth.upgradeWithEmail(...)` calls `_service.upgradeAnonymous(...)` which does `linkWithCredential` + `getIdToken(true)` (force refresh so `sign_in_provider` flips before the Firestore batch) + atomic `users/{uid}` + `usernames/{u}` write + `sendEmailVerification`.
- `linkWithCredential` does NOT always fire `authStateChanges` (same uid) → `upgradeWithEmail` manually replays `_onAuthStateChanged(currentUser)` to transition `anonymous → awaitingVerification`.

### Multi-service (pivot 2026-06-24)

`ServiceType { electricity, water }` lives on each report (default `electricity` at read for backward compat). `Utility { id, service, country, label }` in `lib/config/utilities.dart` replaces the old `ElectricityProvider` — Eneo (CM, elec) + CAMWATER (CM, water). `RegionProvider` exposes `activeUtility(ServiceType)` and a persistent `serviceFilter` (`SharedPreferences`). The settings picker has **two tiles** (one per service) with **symmetric auto-coupling**: setting one slot aligns the other on the same country; picking "Auto" on either side resets both.

### Key providers

- **`AuthProvider`** — wraps `AuthRepository`, drives `AuthGate`. Auto sign-in anonymous on null user (with anti-loop flag); calls `NotificationService.registerForUser` / `unregister` on auth state changes (skipped for anonymous). `refreshVerification` ALSO calls `registerForUser` to enable notifs immediately after email verification (fixed a latent bug where notifs required an app restart).
- **`ReportProvider`** — owns the real-time Firestore stream (`watchReports`), filters/sort state, proximity queries, and all report mutations (confirm, restore, archive). Holds a `_serviceFilter: ServiceType?` (fed from `RegionProvider.serviceFilter` via `AuthGate` proxy) applied **client-side** in `filteredReports` — no Firestore composite index needed. Also implements `WidgetsBindingObserver` to pause/resume the proximity refresh timer when the app goes to background. Tracks the current user's own votes (`iConfirmed`/`iRestored`, set optimistically on action and hydrated from the server via `hydrateMyVotes`) so the UI shows "you already voted".
- **`RegionProvider`** — active country (override → GPS → profile → locale → CM) + `activeUtility(ServiceType)` + persistent `serviceFilter` + 2 dev overrides (one per service) with symmetric auto-coupling.
- **`StatsProvider`** — personal statistics (Profile → Stats): "my outages" (`reportsByAuthor`) and "my area" (`reportsWithinRadius`). Keeps **raw lists**, computes `OutageStats` on demand via `mineFor(ServiceType?)` / `zoneFor(ServiceType?)` — no network reload when the service filter changes. Aggregation logic is a pure, tested function in `lib/utils/outage_stats.dart`.

Cross-cutting services accessed as singletons (not via repositories, like `NotificationService`): `AnalyticsService.instance` (Firebase Analytics — funnel events + `navigatorObservers` screen views; **collection disabled in dev**, never throws into a user flow).

### Proximity filtering

Reports near the user are fetched via geohash bounding box (center + 8 neighbors at the right precision), then filtered by exact distance in Dart — see `lib/utils/geohash.dart` and `ReportRepository.reportsWithinRadius`. This is a one-shot query (not real-time), refreshed every `AppConstants.nearRefreshInterval` or on `pull-to-refresh`.

## i18n

Languages: **FR** (template) and **EN**. ARB source files live in `lib/l10n/`; generated code goes to `lib/l10n/generated/` (gitignored, regenerated by `flutter gen-l10n` / `flutter pub get`).

Always import localizations as:
```dart
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
```

**Validators** are an extension on `AppLocalizations` (`lib/utils/validators.dart`):
```dart
validator: AppLocalizations.of(context).validateEmail
```

**Enum labels and relative times** go through `lib/utils/l10n_helpers.dart`:
```dart
outageStatusLabel(context, report.status)
outageTypeLabel(context, report.type)
serviceTypeLabel(context, report.serviceType)
relativeTimeL10n(context, report.reportedAt)
```

**Service visuals** (icon + color, shared between form selector, chips, markers) go through `lib/widgets/service_visuals.dart`:
```dart
serviceTypeIcon(ServiceType.water)   // Icons.water_drop
serviceTypeColor(ServiceType.water)  // AppColors.water (sky-500)
```

When adding a new string: add the key to `lib/l10n/app_fr.arb` (template) **and** `lib/l10n/app_en.arb`, then run `flutter gen-l10n`.

For ICU plurals in ARB, always add a `"placeholders"` block with `"type": "int"`.

## Firebase & environment

The app has **3 environments**, selected at build time via `--dart-define=APP_ENV=dev|staging|prod` (`AppConfig.environment`, lib/config/app_config.dart):

- **dev** — local Firebase emulators (`main.dart` calls `_connectToEmulators()`), dev tools visible.
- **staging** — online Firebase project **`lightcutoff-dev`**, dev tools (language picker, country/company picker, `STAGING` banner) visible **even in release builds** (`AppConfig.showDevTools`).
- **prod** — dedicated Firebase project, **not created yet**: `main()` throws on `APP_ENV=prod` until `firebase_options_prod.dart` is generated (`flutterfire configure --project=<prod> --out=lib/firebase_options_prod.dart`). Dev tools hidden, no banner.

Backward compatibility: no `APP_ENV` → `staging`; `USE_EMULATOR=true` → `dev`. A `Banner` (top-right corner, `app.dart`) shows DEV/STAGING in non-prod builds. `.firebaserc` has a `staging` alias (→ lightcutoff-dev); add a `prod` alias when the project exists.

On Android emulator the emulator host is auto-resolved to `10.0.2.2`; override with `EMULATOR_HOST` for a physical device.

`lib/firebase_options.dart`, `android/app/google-services.json`, and `ios/Runner/GoogleService-Info.plist` are versioned. Re-generate only if the Firebase project changes:
```bash
flutterfire configure --project=lightcutoff-dev --platforms=android,ios
```

## Widget tests with localization

`pumpAndSettle()` hangs when `SplashScreen` is involved (the `CircularProgressIndicator` never settles). Use two `pump()` calls instead:
```dart
await tester.pump();
await tester.pump(const Duration(milliseconds: 100));
```

Always wrap test widgets that use `AppLocalizations.of(context)` in a `MaterialApp` with:
```dart
localizationsDelegates: AppLocalizations.localizationsDelegates,
supportedLocales: AppLocalizations.supportedLocales,
locale: const Locale('fr'),
```

For unit tests on validators or other `AppLocalizations` consumers without a widget tree:
```dart
final l = await AppLocalizations.delegate.load(const Locale('fr'));
```

## Native constraints

- **Android** `minSdk = 23` (required by `cloud_functions`)
- **Android** Kotlin plugin `2.1.0` (required by `geolocator`)
- **iOS** `platform :ios, '13.0'` (required by Firebase SDKs)
- Debug builds only: cleartext HTTP to emulators is allowed via `android/app/src/debug/res/xml/network_security_config.xml`
- ⚠️ **R8 minification is intentionally OFF for release** (`isMinifyEnabled = false` / `isShrinkResources = false` in `android/app/build.gradle.kts`). With it on (and no `keep` rules), R8 stripped a Firebase plugin's reflection-based registration → **NPE in `FlutterActivity.onCreate`, release crashes on startup** (debug was fine). Do **not** re-enable minify without adding tested ProGuard rules and verifying release launch on a device.

## Data model highlights

See `SCHEMA.md` for the full Firestore schema. Key points for code work:

- **Report soft-delete**: `archivedAt != null` means deleted — filter it in every query. Hard-purge runs via Cloud Function cron after 30 days.
- **Confirmations / Restorations**: subcollections of `reports/{id}`, document ID = `uid` (one vote per user — including anonymous uid). Counter on the parent doc is incremented **client-side in the same atomic transaction** that creates the vote doc. ⚠️ **Security invariant** (`firestore.rules`): a non-author may change a counter only by **+1** *and* only while creating their own vote doc in the same commit (`bumpsCounterByOne` + `castsVote` via `exists`/`existsAfter`). If you ever move the increment elsewhere (e.g. a Cloud Function), you **must** update these rules or the write will be rejected.
- **Auto-resolution**: `onRestorationCreated` Cloud Function triggers when `restorationCount` crosses `max(restorationMinVotes, ceil(confirmationCount × restorationRatio))`. Service-agnostic (works for electricity AND water). Constants live in `AppConstants`.
- **Geohash** precision 6 (≈1.2 km cell) is stored on every report for proximity queries. The `geohash.dart` utility is pure Dart (no plugin dependency).
- **`authorUsername`** on reports is denormalized at creation and immutable — do not update it on profile edits. **`null` for anonymous reports** — `ReportCard` shows NO author reference at all in that case (no chip, no "Anonymous" label — explicit decision 2026-06-24).
- **`serviceType`** on reports: `electricity` (default) or `water`. Legacy reports without the field are read as `electricity` (`ServiceType.fromName(null)`) — no backfill needed. `ReportCard._ServiceChip` shows the service in tile color; map markers (`_ServiceMarker`) overlay a service icon (bolt / water_drop) on the colored pin.
- **`!isAnonymous()`** rule on `users`/`usernames`/`devices` create/update: an anonymous session cannot have a profile, pseudo, or device doc until it upgrades via `linkWithCredential` (which flips `sign_in_provider` to `password` or `google.com`).
- **`AppColors.primary`** is `#F88E01` (amber); `AppColors.dark` is `#1A1A1A` (charcoal); `AppColors.water` is `#0EA5E9` (sky-500).
