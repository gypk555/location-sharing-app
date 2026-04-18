# Code Review — Safety App (location-sharing-app)

**Reviewer:** Claude (Opus 4.7)
**Date:** 2026-04-17 (review) · 2026-04-18 (remediation pass)
**Branch:** `flutter-migration`
**Latest commit at review:** `826c552 Add live location sharing feature`
**Scope:** Flutter app (`flutter_app/lib/`), Security & secrets, Supabase migrations & RLS
**Out of scope (per reviewer request):** `backend/` (Elysia), `mobile/` (legacy React Native)

---

## 0. Remediation Status (2026-04-18)

All findings below are annotated inline with one of:

- **✅ FIXED** — landed in this branch. The original finding is preserved verbatim for history; a **Fix (2026-04-18):** block underneath describes the change.
- **⚠️ DEFERRED** — acknowledged but not implemented in this pass; rationale in-line.
- no tag — observational / info-only, no action required.

| Finding | Status | Short note |
|---|---|---|
| §3.1 Test coverage ≈ 0 | ✅ PARTIALLY FIXED | `test/shared/utils/validators_test.dart` seeded; larger pyramid still outstanding |
| §3.2 `ContactsNotifier` oversized (1085 LOC) | ✅ FIXED | Supabase work extracted to `ContactsSyncManager` |
| §3.3 `HomeScreen` oversized (952 LOC) | ✅ FIXED | Home split across `features/home/widgets/*.dart` |
| §3.4 `BackgroundService.stopSharing` fire-and-forget | ✅ FIXED | Retry loop with 500/1000/2000 ms back-off |
| §3.5 `e.toString()` error leakage | ⚠️ DEFERRED | Sealed `AuthFailure` work sized L; tracked separately |
| §3.6 Route strings are magic literals | ✅ FIXED | `lib/app/routes.dart` + migrated callers |
| §3.7 `_AuthNotifier` never disposed | ✅ FIXED | `ref.onDispose(authNotifier.dispose)` added |
| §3.8 Password-reset TODOs | ⚠️ DEFERRED | Feature work; same deferral as SECURITY_REVIEW L-3 |
| §4 SOS background / lock screen | ⚠️ DEFERRED | OEM-level work; needs device testing matrix |
| §5.1 `.env` bundled guard comment | ✅ FIXED (via SECURITY_REVIEW I-4) | `.env.example` now carries "Development only" note |
| §5.2 Hive unencrypted | ✅ FIXED (via SECURITY_REVIEW H-2) | `SecureHive` + `flutter_secure_storage` |
| §5.3 No cert pinning | ⚠️ DEFERRED (via SECURITY_REVIEW M-6) | Decision documented; rely on platform TLS |
| §5.4 `CALL_PHONE` runtime check | ⚠️ DEFERRED | Low risk (fake-call flow); tracked |
| §5.6 Crashlytics wiring | ⚠️ DEFERRED | Requires adding `firebase_crashlytics` dep |
| §6.3.x Migration robustness | — | Observations only; no blocking issues |
| §7.1 `Semantics` on SOS button | ✅ FIXED | Wrapped in `Semantics(button, label, hint, onTapHint, onLongPressHint)` |
| §7.2 i18n | ⚠️ DEFERRED | Tracked; SOS-first plan remains |
| §2.2 Tighter lints | ✅ FIXED | `analysis_options.yaml` enables `unawaited_futures`, `avoid_print`, etc. |

**Post-remediation file sizes:**

| File | Before | After |
|---|---:|---:|
| `lib/features/home/screens/home_screen.dart` | 952 | 421 |
| `lib/core/providers/contacts_provider.dart` | 1086 | 1003 |
| `lib/core/services/contacts_sync_manager.dart` | (new) | 221 |
| `lib/features/home/widgets/*.dart` | — | 8 files, avg ~70 LOC |

---

## 1. Executive Summary

This is a Flutter-based Women & Child Safety application targeting 100K+ users in India. It combines offline-first local storage (Hive), Supabase Postgres with RLS, and a Flutter background isolate for live location sharing. The repository shows **strong foundations** — particularly the Supabase migrations, the background-isolate architecture, and the input-validation layer — but has several **ship-blocking gaps** for a safety-critical app: effectively zero test coverage, unencrypted local storage of emergency contacts, and missing accessibility labels on the SOS button. The stated CLAUDE.md requirement that SOS "must work offline, background, lock screen" is only partially met.

### 1.1 Issue counts by severity

| Severity | Count | Notes |
|----------|------:|-------|
| **P0 — Ship-blocker** | 3 | Hive encryption, test coverage, SOS background path |
| **P1 — Pre-launch** | 6 | a11y, i18n, cert pinning, god-widgets, route constants, recording feature |
| **P2 — Next iteration** | 7 | refactors, FCM wiring, dependency audit, OTP persistence, etc. |
| **INFO / LOW** | 4 | `.env` asset bundling, password-reset TODOs, logger Crashlytics, etc. |

### 1.2 Top 10 ranked by user impact × effort

| # | Issue | File(s) | Severity | Effort |
|---|-------|---------|---------:|-------:|
| 1 | Hive boxes unencrypted — emergency contacts + location history in plaintext | `lib/main.dart:55` | P0 | M |
| 2 | Test coverage ≈ 0 (one smoke test) | `test/widget_test.dart` | P0 | L |
| 3 | SOS shake detection only works while main isolate is alive | `lib/core/services/sos_service.dart:62` | P0 | L |
| 4 | No `Semantics` / labels on SOS button — blind users can't trigger SOS | `lib/features/sos/screens/sos_screen.dart` | P1 | S |
| 5 | No i18n — India-focused app, English-only | all features | P1 | L |
| 6 | No certificate pinning for Supabase | `lib/main.dart` + Android/iOS net config | P1 | M |
| 7 | HomeScreen is 952 lines, mixes 5 concerns | `lib/features/home/screens/home_screen.dart` | P1 | M |
| 8 | ContactsNotifier is 1085 lines, mixes sync + CRUD + state | `lib/core/providers/contacts_provider.dart` | P1 | M |
| 9 | Route strings are magic literals | `lib/app/router.dart` + all callers | P1 | S |
| 10 | Error `toString()` leakage in auth/contacts | `lib/core/providers/auth_provider.dart:141` etc. | P2 | S |

### 1.3 Verdict

Not ready for a 100K+-user general-availability launch today; **could be ready within ~2 sprints** if the P0 items are addressed and a minimum test pyramid is in place. The code you already have in `background_service.dart`, `supabase/migrations/`, and `validators.dart` is genuinely good engineering — the gaps are coverage, hardening, and feature completion, not architectural confusion.

---

## 2. Architecture & Structure

### 2.1 Layer organization

```
flutter_app/lib/
├── app/              router.dart, app.dart (ConsumerStatefulWidget root)
├── core/
│   ├── models/       Hive-backed: UserModel, ContactModel, LocationModel
│   ├── providers/    6 Riverpod notifiers (auth, sos, live_sharing, contacts, location, password_breach)
│   └── services/     10 services (auth, sos, location, background, sms, ...)
├── features/         auth, home, sos, contacts, live_sharing, fake_call, settings
└── shared/           constants, errors, theme, utils (validators, logger), widgets
```

The layering is clean and consistent. `features/live_sharing/` is the only feature with its own `providers/` subdirectory — this is actually a good pattern that should be propagated to the other features as they grow (see §3.2 and §3.3).

### 2.2 Dependency audit (`pubspec.yaml`)

| Package | Pinned | Concern |
|---------|--------|---------|
| `flutter_riverpod` | `^2.5.1` | OK. Riverpod 3.x is out; plan a future bump. |
| `go_router` | `^14.2.0` | OK. |
| `flutter_background_service` | `^5.0.10` | ⚠ Plugin is comparatively quiet; it touches iOS private APIs. Monitor for iOS rejections and be prepared to migrate to a first-party alternative if iOS support breaks on a new major OS. |
| `disable_battery_optimization` | `^1.1.1` | ⚠ Unmaintained. OEM battery policies (Xiaomi/Oppo/Vivo) shift frequently in India. You've already built `oem_battery_service.dart` on top — consider fully in-housing this logic so the dependency can be removed. |
| `firebase_messaging`, `firebase_core` | `^15.0.0`, `^3.5.0` | ⚠ Imported but no `FirebaseMessaging.instance.onMessage` handler visible. Recipients of live shares won't get push-re-activation; cold-start the app and they miss the session. Wire this up before shipping. |
| `record`, `audioplayers` | `^6.2.0`, `^6.0.0` | Present but the Audio/Video Recording feature (CLAUDE.md priority #5) is not implemented. Fake Call audio is deliberately deferred per CLAUDE.md. |
| `flutter_dotenv` | `^5.1.0` | OK; but see §5.1 on `.env` bundling. |

**Linter.** `analysis_options.yaml` uses stock `flutter_lints` with no custom rules. Consider adding `very_good_analysis` or at least enabling:

```yaml
linter:
  rules:
    - avoid_print
    - prefer_const_constructors
    - prefer_const_declarations
    - unawaited_futures
    - avoid_dynamic_calls
```

### 2.3 Service-layer inventory

| Service | LOC | Role | Notes |
|---------|---:|------|-------|
| `location_service.dart` | 415 | Tiered geolocator stream, geocoding with cache | Singleton. Has explicit `markAsBackgroundIsolate()` — good. |
| `live_location_sharing_service.dart` | 522 | Session lifecycle, per-recipient rows, RPC calls | 144-line `_createSession` orchestrator — split candidate. |
| `background_service.dart` | 393 | Android FGS + iOS background isolate | Well-commented. See §3.4. |
| `sos_service.dart` | 260 | Shake detection, countdown, broadcast | Solid state machine; disposal is correct. |
| `auth_service.dart` | 370+ | Phone/email/Google/Apple, OTP, Supabase session | See §3.5. |
| `contacts_backup_service.dart` | 373 | Supabase sync with hashing/dedup | Pairs with `contacts_provider.dart` (see §3.3). |
| `sms_service.dart` | 319 | SMS / WhatsApp deep links | `url_launcher`-based. |
| `oem_battery_service.dart` | 112 | OEM detection + autostart prompting | Good — India-specific handling. |
| `password_breach_service.dart` | 172 | HaveIBeenPwned k-anonymity lookup | See §5 — nice security practice. |
| `fake_call_service.dart` | — | Incoming-call UI; audio deferred (CLAUDE.md) | — |

---

## 3. Critical Code-Quality Findings

Each finding has a file:line reference, a snippet, and a proposed patch.

### 3.1 — P0 — Test coverage is a single smoke test · ✅ PARTIALLY FIXED

**Location:** `flutter_app/test/widget_test.dart`

```dart
testWidgets('SafetyApp smoke test', (WidgetTester tester) async {
  await tester.pumpWidget(const ProviderScope(child: SafetyApp()));
  expect(find.byType(MaterialApp), findsOneWidget);
});
```

**Problem.** That is the *entire* test suite for a 100K-user safety app. Any regression in SOS, location, auth, contacts, validators, or migrations will reach users. For a safety product this is a ship-blocker.

**Proposed minimum test pyramid (prioritized):**

1. **`Validators` unit tests** (fast, high value — guards all input paths):
   ```dart
   // test/shared/utils/validators_test.dart
   test('normalizes Indian phone to E.164', () {
     expect(Validators.normalizePhone('9876543210'), '+919876543210');
     expect(Validators.normalizePhone('+91 98765 43210'), '+919876543210');
     expect(Validators.normalizePhone('invalid'), isNull);
   });
   ```
2. **`SosNotifier` state-machine tests** using `StateNotifierProvider.overrideWith`:
   ```dart
   test('SOS: idle → countdown → sent on success path', () async {
     final container = ProviderContainer(overrides: [
       sosServiceProvider.overrideWithValue(FakeSosService.success()),
     ]);
     final notifier = container.read(sosStatusProvider.notifier);
     await notifier.trigger();
     expect(container.read(sosStatusProvider), SosStatus.sent);
   });
   ```
3. **`AuthNotifier` hydration tests** — cached user → Hive user → server user order.
4. **Hive persistence round-trip tests** — write `ContactModel`, close, reopen, read back.
5. **Widget test for SOS countdown** — taps button, waits 5s, asserts `_smsService.sendSosAlert` called.
6. **Golden test** for `LiveMapView` rendering at a known lat/lng.

Add to CI and require passing before merge. Target: 60% line coverage on `lib/core/**` within one sprint.

**Fix (2026-04-18):** Seeded the first tier of the pyramid at `flutter_app/test/shared/utils/validators_test.dart`. Covers:

- `normalizePhone` — Indian 10-digit prefixing, formatting strip, country-code preservation, Unicode-digit-bypass sentinel, E.164 round-trip.
- `isValidE164` — standard accept cases + `+0…`, missing `+`, and non-digit rejects.
- `validatePassword` — length, char-class, common-list, sequential-digit, accept path.
- `containsSqlInjection` — UNION / DROP payloads flagged, benign SQL-word names not flagged, null/empty safe.

`SosNotifier`, `AuthNotifier`, Hive round-trip, and the countdown widget test remain open — the scope exceeds this remediation pass and depends on introducing `FakeSosService` / `FakeAuthService` harnesses, which the existing code isn't structured for. CI wiring also deferred.

### 3.2 — P1 — `ContactsNotifier` is 1085 lines and mixes concerns · ✅ FIXED

**Location:** `lib/core/providers/contacts_provider.dart` (1085 lines)

**Problem.** A single `StateNotifier` handles:
- Local CRUD on the Hive box
- Supabase cloud sync
- Retry / backoff
- SOS contact filtering
- Primary-contact enforcement
- Error surfacing to UI

At this size any refactor is high-risk and the surface area is hard to test.

**Proposed split:**

```
lib/core/
├── services/
│   └── contacts_sync_manager.dart    // Cloud sync, hashing, dedup, retry
└── providers/
    ├── contacts_provider.dart        // Just Hive CRUD + UI state (≤ 300 lines)
    └── contacts_sync_provider.dart   // Exposes sync status for UI badges
```

`ContactsSyncManager` wraps `contacts_backup_service.dart` and becomes the only thing the notifier talks to for remote work — the notifier itself becomes a thin orchestrator over the local Hive box.

**Fix (2026-04-18):** Landed `lib/core/services/contacts_sync_manager.dart` (221 LOC). It owns every Supabase-specific call that used to live on the notifier:

- `pushUnsyncedBatch(userId, unsynced)` — 50-contact chunks, with per-row fallback when the batch upsert fails.
- `pushOne(userId, contact, isNew)` — returns `PushOutcome.success|failure`; callers flip `isSynced` locally only on success.
- `fetchRemote(userId)` — pulls remote rows; merging + Hive persistence stays on the notifier so the Hive mutex is never touched from outside.
- `deleteOne(userId, contactId)` and `retryPendingDeletes(userId, pendingIds)` — returns the set of IDs successfully removed so the notifier can prune `pendingDeletes`.
- `isOnline()` + `onConnectivityChanged()` — centralizes the `connectivity_plus` probe and stream.

The notifier now delegates every Supabase touch-point through the manager, keeping Hive mutex, state mutations, debouncing, and input validation. Net effect: 1086 → 1003 LOC on the notifier, with the extracted 221 LOC centralized and independently testable.

**Not done in this pass:** further split into (c) Hive persistence and (d) import/export adapters. The remaining size on `ContactsNotifier` is mostly input-validation + state transitions, which don't cleanly factor without reshaping the public API used by callers.

### 3.3 — P1 — `HomeScreen` is 952 lines · ✅ FIXED

**Location:** `lib/features/home/screens/home_screen.dart` (952 lines)

**Problem.** The home screen renders: password-breach warning banner, incoming-shares list, quick-actions grid, SOS contact sync status, location error banner, and greeting card — all in one file with one `build`.

**Proposed extraction:**

```dart
// lib/features/home/screens/home_screen.dart  (≤ 200 lines)
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          children: const [
            GreetingHeader(),
            LocationErrorBanner(),
            BreachWarningBanner(),
            IncomingSharesSection(),
            QuickActionsGrid(),
            SosContactSyncCard(),
          ],
        ),
      ),
    );
  }
}

// Each of the above moves into lib/features/home/widgets/*.dart
```

Each extracted widget becomes testable in isolation and rebuildable without redrawing the world.

**Fix (2026-04-18):** Moved every visual section into `lib/features/home/widgets/`:

- `home_welcome_card.dart` (greeting + avatar + "Stay safe today").
- `location_status_card.dart` (tracking switch + current address readout).
- `location_error_card.dart` (conditional warning banner; renders `SizedBox.shrink()` when there is no error — safe to unconditionally include).
- `incoming_shares_banner.dart` (was `_IncomingSharesBanner`).
- `quick_action_card.dart` (was `_QuickActionCard`).
- `quick_actions_grid.dart` (the 2×2 grid; receives `onShareLocation` callback because share-flow state lives on the screen).
- `app_chooser_dialog.dart` (was `_AppChooserDialog` + `_AppIcon`).
- `safety_tip_card.dart`.

`HomeScreen` drops from 952 → 421 LOC and now contains only side-effectful concerns the extracted widgets can't own: the `WidgetsBindingObserver` lifecycle hooks, the `ProviderSubscription<LocationState>` error-banner listener, the breach-warning `MaterialBanner`, and the four `_shareVia*` methods (coupled to `SmsService` + `ScaffoldMessenger` + `mounted` guards). Each widget averages ~70 LOC and rebuilds independently.

### 3.4 — P2 — `BackgroundService.stopSharing()` is fire-and-forget · ✅ FIXED

**Location:** `lib/core/services/background_service.dart:172-186`

```dart
static Future<void> stopSharing() async {
  final service = FlutterBackgroundService();
  service.invoke('stop');
  unawaited(
    Future<void>.delayed(const Duration(seconds: 2)).then((_) async {
      try {
        if (await service.isRunning()) {
          AppLogger.warning('bg: stop event was not honored within 2s');
        }
      } catch (_) {}
    }),
  );
}
```

**Assessment.** The code already acknowledges this limitation in a comment. The warning log is helpful but **never makes it off the device** because `AppLogger` is debug-only (see §5.6). On a real user's device, a stuck foreground notification is never telemetered.

**Proposed patch:** replace the single-shot 2s check with a short retry loop, and route the "stuck" signal to Crashlytics/Sentry (once wired — see §5.6):

```dart
static Future<void> stopSharing() async {
  final service = FlutterBackgroundService();
  service.invoke('stop');
  await _confirmStopped(service);
}

static Future<void> _confirmStopped(FlutterBackgroundService service) async {
  const delays = [500, 1000, 2000]; // ms, exponential-ish
  for (final ms in delays) {
    await Future<void>.delayed(Duration(milliseconds: ms));
    try {
      if (!await service.isRunning()) return;
    } catch (_) { return; }
    service.invoke('stop'); // re-send in case it was dropped
  }
  AppLogger.warning('bg: stop not honored after ${delays.length} retries');
  // TODO: when Crashlytics is wired, recordError here.
}
```

**Fix (2026-04-18):** Landed at `lib/core/services/background_service.dart:172-198`. `stopSharing` now calls `_confirmStopped` which polls `isRunning()` on a `[500, 1000, 2000]` ms schedule, re-invoking `stop` each iteration so a dropped event on the plugin's method channel gets a second chance. When all three attempts fail we log a warning and leave a `TODO:` anchor for the Crashlytics `recordError` call once §5.6 lands.

### 3.5 — P2 — Error `toString()` leakage in auth/contacts notifiers · ⚠️ DEFERRED

**Location:** `lib/core/providers/auth_provider.dart` (every handler, e.g. line 141)

```dart
} catch (e) {
  _safeSetState(state.copyWith(isLoading: false, error: e.toString()));
}
```

**Problem.** This surfaces raw `PostgrestException`/`AuthException` messages (including internal error codes, sometimes SQL fragments) directly into UI state. Compare with the better pattern already in use in `lib/core/providers/live_sharing_provider.dart`, which has discriminated failure types (`AuthFailure`, `DatabaseFailure`, `UnknownFailure`).

**Proposed patch:**

```dart
// lib/core/errors/auth_failure.dart
sealed class AuthFailure {
  const AuthFailure();
}
class InvalidCredentials extends AuthFailure { const InvalidCredentials(); }
class EmailNotFound    extends AuthFailure { const EmailNotFound(); }
class OtpExpired       extends AuthFailure { const OtpExpired(); }
class NetworkFailure   extends AuthFailure { const NetworkFailure(); }
class UnknownAuthFailure extends AuthFailure {
  const UnknownAuthFailure(this.cause);
  final Object cause;
}

// In auth_provider.dart
} on AuthException catch (e) {
  _safeSetState(state.copyWith(
    isLoading: false,
    failure: _mapSupabaseAuthError(e),
  ));
} catch (e, st) {
  AppLogger.error('Unexpected auth error', e, st);
  _safeSetState(state.copyWith(
    isLoading: false,
    failure: UnknownAuthFailure(e),
  ));
}
```

Then the UI layer translates the sealed type into a localized, user-friendly string. No raw Supabase errors leak.

**Deferred (2026-04-18):** Rationale — the refactor is an API change on the notifier's `state.error` contract, and every caller (screens, banners, validation paths) has to switch from `String?` to the new sealed type in the same PR. Doing this alongside the oversized-file splits in the same pass was too large a blast radius. Tracked for a follow-up diff scoped only to errors.

### 3.6 — P1 — Route strings are magic literals · ✅ FIXED

**Location:** `lib/app/router.dart` + every call site (`context.push('/add-contact')`, `context.go('/')`, etc.).

**Proposed patch:** a single `AppRoutes` constants class:

```dart
// lib/app/routes.dart
abstract final class AppRoutes {
  static const splash = '/splash';
  static const auth = '/auth';
  static const otp = '/otp';
  static const home = '/';
  static const sos = '/sos';
  static const contacts = '/contacts';
  static const addContact = '/add-contact';
  static const settings = '/settings';
  static const fakeCall = '/fake-call';
  static const liveShareStart = '/live-share/start';
  static const liveShareActive = '/live-share/active';
  static String liveShareView(String id) => '/live-share/view/$id';
}
```

Then update `router.dart` and every caller. `flutter analyze` will find all untyped strings if you delete the file and rely on compile errors. This also becomes the single place to refactor route-prefix schemes later.

**Fix (2026-04-18):** Landed `lib/app/routes.dart` as an `abstract final class AppRoutes` exposing `splash`, `auth`, `otp`, `home`, `sos`, `contacts`, `settings`, `addContact`, `fakeCall`, `liveShareStart`, `liveShareActive`, `liveShareViewPattern`, and the `liveShareView(String id)` URL builder. Migrated every live caller: `router.dart`, `main_scaffold.dart`, `home_screen.dart`, `contacts_screen.dart`, `unified_auth_screen.dart`, `active_share_screen.dart`, `start_share_screen.dart`. The dead `/login` / `/register` literals in `login_screen.dart` / `register_screen.dart` were intentionally left alone — those screens are superseded by `unified_auth_screen.dart` and are scheduled for removal.

### 3.7 — P2 — `_AuthNotifier` is recreated on every `routerProvider` rebuild · ✅ FIXED

**Location:** `lib/app/router.dart:22-30`

```dart
class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier(this._ref) {
    _ref.listen(authStateProvider, (prev, next) => notifyListeners());
  }
  final Ref _ref;
}

final routerProvider = Provider<GoRouter>((ref) {
  final authNotifier = _AuthNotifier(ref);
  return GoRouter(...);
});
```

**Problem.** `Provider<GoRouter>` is itself a `Provider`, so it's cached — but `_AuthNotifier` is never `dispose`d. The `ref.listen` registers a listener that's never removed if the provider is ever recreated (e.g. during `ProviderScope` disposal in tests, or a future `ref.invalidate(routerProvider)`).

**Proposed patch:**

```dart
final routerProvider = Provider<GoRouter>((ref) {
  final authNotifier = _AuthNotifier(ref);
  ref.onDispose(authNotifier.dispose);
  return GoRouter(
    refreshListenable: authNotifier,
    ...
  );
});
```

Small but correct.

**Fix (2026-04-18):** Added `ref.onDispose(authNotifier.dispose)` at `lib/app/router.dart:30` right after construction. The listener is now released on provider invalidation / `ProviderScope` teardown.

### 3.8 — LOW — Two unresolved `TODO`s for password reset · ⚠️ DEFERRED

```
lib/features/home/screens/home_screen.dart:139  // TODO: Navigate to change password screen when implemented
lib/features/auth/screens/login_screen.dart:140  // TODO: Navigate to change password screen when implemented
```

**Action.** Either implement the flow (Supabase `resetPasswordForEmail` + a deep-link handler) or convert to issue-tracker tickets and remove the TODOs. A safety app without password recovery leaves users locked out and motivated to re-register with fresh accounts, losing their emergency-contact history.

**Deferred (2026-04-18):** Feature work (needs product decisions on the UX / deep-link scheme / deep-link interception on both platforms). Matches SECURITY_REVIEW L-3 disposition.

---

## 4. Safety-Critical Feature Gaps (vs. CLAUDE.md Requirements) · ⚠️ DEFERRED

CLAUDE.md states:

> 1. **SOS Alert** — Must work offline, background, lock screen
> 2. **Location Sharing** — Battery efficient, accurate
> 3. **Emergency Contacts** — Encrypted, easily accessible
> 4. **Fake Call** — Quick access, convincing
> 5. **Audio/Video Recording** — Discreet, auto-upload when online

Reality check:

| Requirement | Status | Notes |
|-------------|--------|-------|
| SOS offline | ✅ | SMS path does not require network; `sms_service.dart` uses `sms:` / `smsto:` URI schemes. |
| SOS background | ⚠ PARTIAL | `sos_service.dart:62` registers `accelerometerEventStream()` in the **main** isolate. When Android kills the main activity (very likely on Chinese OEMs even with `oem_battery_service.dart`), the shake listener dies. No foreground service dedicated to SOS detection. |
| SOS lock screen | ❌ | No `android:showWhenLocked` / `android:turnScreenOn` on the SOS activity. No quick-settings tile. No notification-trigger action. |
| SOS hardware trigger (volume / power) | ❌ | Not implemented. Typical Indian OEMs expose this via accessibility services; this is the usual pattern for distress apps. |
| Battery efficiency | ✅ | `location_service.dart` has a tiered accuracy model (normal/stationary/emergency). Good. |
| Encrypted emergency contacts | ❌ | `Hive.initFlutter()` in `lib/main.dart:55` with **no cipher**. See §5.2. |
| Fake Call convincing | ⚠ | Realistic UI present, but CLAUDE.md acknowledges audio assets are missing. |
| Audio/Video Recording | ❌ | `record` + `audioplayers` are in pubspec but no service/UI. Priority #5, deferred. |
| FCM push for live-share recipients | ❌ | Dep present (`firebase_messaging`), not wired. Receivers joining mid-share get no notification. |

**Most urgent of these:** SOS reliability on backgrounded/locked devices. Without it, the product's headline feature fails silently exactly when it's needed. The concrete path is:
1. Promote SOS shake detection into the existing foreground service (same isolate that already runs for live sharing) so it keeps running even with the main activity killed.
2. Add a `QuickSettingsTile` (Android) / Control Center widget (iOS 14+) to trigger SOS from the lock screen.
3. Stretch goal: volume-button trigger via an `AccessibilityService`. Disclose the permission carefully — Google Play scrutinizes accessibility-service use.

**Deferred (2026-04-18):** Each of these items involves device-specific behavior (Xiaomi/Redmi/Oppo/Vivo battery policies, iOS background-modes quirks, Android lock-screen and quick-settings API changes). Shipping without a matrix of real-device tests across Chinese OEMs is riskier than the current partial posture — we'd generate false confidence in a "fixed" SOS that silently dies on a locked Mi. Tracked as a discrete sprint.

---

## 5. Security Review

### 5.1 — INFO — `.env` is bundled as a Flutter asset · ✅ FIXED (via SECURITY_REVIEW I-4)

**Location:** `flutter_app/pubspec.yaml` lines 98-99, and `flutter_app/.env` (lines 2-7 contain real values).

```yaml
flutter:
  uses-material-design: true
  assets:
    - .env
```

```
SUPABASE_URL=https://eyqiqzssbbkgloeoncuk.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1Ni... (full JWT)
NEXT_PUBLIC_SUPABASE_URL=...
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_DEFAULT_KEY=sb_publishable_...
```

**Assessment.** Confirmed facts:
- `.env` is in `flutter_app/.gitignore` (line 19), and `git log --all -- flutter_app/.env` returns no history — so the secrets have **not** been committed to git.
- But `assets: [- .env]` **does** bundle `.env` into every APK/IPA. Anyone who unzips the APK can read it.
- The exposed keys are the **anon key** and the **publishable key**. Both are *designed* to be public in Supabase's model — access is gated by RLS. So this is **not a leak in the classical sense** (downgrade from the initial scan's CRITICAL to INFO).
- **However**: future maintainers might reflexively add a `SERVICE_ROLE_KEY` or a third-party API key to the same `.env` because the asset-bundling convention is already established. That would be catastrophic.

**Proposed patch:** add a loud guard comment to `.env.example`:

```dotenv
# ============================================================
# WARNING: This file ships inside the Flutter APK/IPA as an asset
# (see pubspec.yaml: flutter.assets). ONLY put values here that
# are safe to expose publicly. In particular:
#
#   - Supabase ANON key → OK (designed to be public, gated by RLS)
#   - Supabase publishable key → OK
#   - Supabase SERVICE ROLE key → NEVER put it here
#   - Twilio auth tokens → NEVER put them here
#   - Any payment / provider secret → NEVER
#
# Server-side-only secrets belong in backend/.env, not here.
# ============================================================
```

### 5.2 — P0 / MEDIUM — Hive boxes are unencrypted · ✅ FIXED (via SECURITY_REVIEW H-2)

**Location:** `lib/main.dart:55-60`

```dart
await Hive.initFlutter();
Hive.registerAdapter(UserModelAdapter());
Hive.registerAdapter(ContactModelAdapter());
Hive.registerAdapter(LocationModelAdapter());
```

**Problem.** Emergency-contact names, phone numbers, relationships, and location history are serialized to the app's internal-storage directory **in plaintext**. On a rooted Android device, a lost-and-found iPhone with a jailbreak, a device-management vendor's data-extraction tool, or an ADB backup — all of these expose the victim's entire support network to whoever has the device. For a women's-safety app specifically, this is the data you least want leaked.

**Proposed patch:**

Add `flutter_secure_storage` to `pubspec.yaml`:

```yaml
dependencies:
  flutter_secure_storage: ^9.2.2
```

Create a helper:

```dart
// lib/core/services/hive_encryption.dart
import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

class HiveEncryption {
  static const _keyStorageKey = 'hive_aes_key_v1';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static Future<HiveAesCipher> cipher() async {
    final existing = await _storage.read(key: _keyStorageKey);
    if (existing != null) {
      return HiveAesCipher(base64Decode(existing));
    }
    final keyBytes = Hive.generateSecureKey(); // 32-byte AES-256 key
    await _storage.write(key: _keyStorageKey, value: base64Encode(keyBytes));
    return HiveAesCipher(keyBytes);
  }
}
```

Update `main.dart` and every `Hive.openBox<T>(name)` call (search for them):

```dart
final cipher = await HiveEncryption.cipher();
await Hive.openBox<ContactModel>(
  AppConstants.contactsBoxName,
  encryptionCipher: cipher,
);
```

**Migration path.** Existing users on the current release already have plaintext boxes. You need a one-shot migration:
1. On first launch after upgrade, open the plaintext box, copy values into a new encrypted box under a different name, delete the old box, rename or leave behind a flag.
2. Gate this behind a `SharedPreferences` `hive_migrated_to_encrypted_v1` boolean to make it idempotent.

### 5.3 — P1 / MEDIUM — No certificate pinning for Supabase · ⚠️ DEFERRED (via SECURITY_REVIEW M-6)

**Location:** `lib/main.dart` calls `Supabase.initialize(url, anonKey)` with no `HttpClient` override. No `res/xml/network_security_config.xml` in `android/app/src/main/res/`. No iOS `NSAppTransportSecurity` pinning in `ios/Runner/Info.plist`.

**Risk.** On a rooted device or one where the user has installed a rogue trust anchor (common in India via fake "VPN" apps), a MITM adversary can intercept live location data. This matters more than usual because location is the adversary's primary target.

**Proposed patch — Android side:**

```xml
<!-- android/app/src/main/res/xml/network_security_config.xml -->
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
  <base-config cleartextTrafficPermitted="false"/>
  <domain-config>
    <domain includeSubdomains="true">supabase.co</domain>
    <pin-set expiration="2027-12-31">
      <!-- Replace with the SHA-256 of your Supabase cert's SPKI.
           Keep at least one backup pin (the issuing CA's intermediate). -->
      <pin digest="SHA-256">AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=</pin>
      <pin digest="SHA-256">BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=</pin>
    </pin-set>
  </domain-config>
</network-security-config>
```

Reference it in `AndroidManifest.xml`:

```xml
<application
    android:networkSecurityConfig="@xml/network_security_config"
    ...>
```

**iOS side:** use `TrustKit` (or `http_certificate_pinning` plugin) and run Supabase client through a pinned `Dio` instance.

**Operational caveat.** Bad pinning bricks your app if Supabase rotates certs. You must (a) ship backup pins, (b) monitor cert expiry with alerts, (c) have a kill-switch (remote config flag) to disable pinning if you need to recover.

### 5.4 — Positive — Android permissions are well-scoped

**Location:** `flutter_app/android/app/src/main/AndroidManifest.xml`

Good choices already made:
- Legacy storage gated on SDK version (`maxSdkVersion="28"` / `"32"`).
- `READ_MEDIA_AUDIO` explicitly *omitted* with a comment saying why — this is rare and correct.
- No `READ_SMS` — send-only via `url_launcher`.
- No `BIND_ACCESSIBILITY_SERVICE` (would be needed for volume-button SOS — flag this for the §4 work).
- `FOREGROUND_SERVICE_LOCATION` declared (required Android 14+).

**One runtime gap.** `CALL_PHONE` is declared but I don't see a runtime request before a call is placed. Check `fake_call_service.dart` and wrap the call with `Permission.phone.request()` before dialing.

### 5.5 — Positive — Input validation is strong

**Location:** `lib/shared/utils/validators.dart` (567 lines)

The file contains:
- Email validation.
- E.164 phone validation specifically for Indian numbers.
- Strong password rules (8+ chars, mixed case, numbers, specials).
- HaveIBeenPwned k-anonymity check via `password_breach_service.dart`.
- XSS sanitization (`sanitizeInput`, `containsXss`) — not strictly needed for a native Flutter app but nice defense-in-depth in case anything ever gets rendered into a `WebView`.
- Regex guards against SQL-style injection primitives (defense-in-depth; Supabase parameterizes server-side).

**Keep this pattern; propagate it.** The backend (`backend/`, out of scope for this review) should mirror these validators exactly — never trust the client for a safety app.

### 5.6 — Positive, with one suggestion — Logger is debug-only · ⚠️ DEFERRED

**Location:** `lib/shared/utils/logger.dart`

```dart
static void error(String message, [Object? error, StackTrace? stackTrace]) {
  if (kDebugMode) {
    debugPrint('[ERROR] $message');
    ...
  }
  // In production, send to crash reporting service like Firebase Crashlytics
  // if (!kDebugMode) {
  //   FirebaseCrashlytics.instance.recordError(error, stackTrace);
  // }
}
```

Excellent: zero production log statements outside `kDebugMode`, so no PII reaches user-accessible logs. `grep` for `print(` / `debugPrint(` across `lib/` returns only this file.

**Suggestion.** Wire the commented-out Crashlytics block — you already depend on `firebase_core`. Without a crash reporter you have no production visibility; issues like §3.4 ("stop not honored") never reach you. Redact PII before sending:

```dart
if (!kDebugMode) {
  FirebaseCrashlytics.instance.recordError(
    error,
    stackTrace,
    reason: message, // generic context, never user data
    fatal: false,
  );
}
```

**Deferred (2026-04-18):** Requires adding `firebase_crashlytics` to `pubspec.yaml`, initialising it in `main.dart`, and uploading the debug symbols / dSYMs during the Android and iOS build — none of which are currently wired. A PII-redaction policy also needs to exist before we start recording errors. Tracked alongside the FCM wire-up (§2.2 `firebase_messaging` is also unconfigured) as a single Firebase bootstrap diff.

---

## 6. Supabase Migrations & RLS Review

There are two migration files. Both are **very well written** — comments explain the *why*, security trade-offs are called out, and idempotency is considered. Praise first, then findings.

### 6.1 — `001_fix_search_path.sql` — ✅ Strong

Applies `SET search_path = ''` to every function in `public`, including the `SECURITY DEFINER` ones (`handle_new_user`, `get_latest_location`). This is the correct defense against CVE-2018-1058 search-path injection, and the comment correctly explains why the empty-string form is the tightest option. The verification query at the bottom is a nice touch.

### 6.2 — `002_live_sharing.sql` — ✅ Strong, with observations

Highlights worth calling out:

- **`get_live_share()` deliberately excludes the reverse-geocoded `address`** (lines 64-67). The comment explicitly names the doxxing vector (SMS/WhatsApp forwarding of share links). This is the kind of threat modeling a safety app needs.
- **`find_user_by_phone()` is gated by the caller's own `emergency_contacts`** (lines 143-160). Prevents mass enumeration of registered users — a real abuser pattern. Good.
- **24-hour hard cap on `expire_location_shares()`** (lines 178-194). Even NULL-`expires_at` sessions get terminated. Defense against orphaned background services exfiltrating location indefinitely.
- **`REPLICA IDENTITY FULL`** on `location_sharing` and `location_history` (lines 267-268). Required for realtime UPDATE events to pass RLS — the comment explains why. Many teams miss this and ship a broken end-of-share UX.
- **Recipient SELECT policy drops the `is_active = TRUE` filter** (lines 271-292). The comment is correct that the old filter broke realtime UPDATE visibility. Good decision; the trade-off is now documented.

### 6.3 — Minor migration findings

| # | Finding | Severity | Fix |
|---|---------|---------:|-----|
| 6.3.1 | `CHECK (trigger_source IN ('manual','sos'))` with a `DEFAULT 'manual'` is added via `ADD COLUMN IF NOT EXISTS` (line 26). If this migration runs on a table that already has the column with a different check constraint, PostgreSQL will silently skip the column, so the `CHECK` won't be enforced. | LOW | After the `ALTER TABLE`, explicitly `ALTER TABLE ... DROP CONSTRAINT IF EXISTS ...` and re-add, or verify with `pg_constraint`. |
| 6.3.2 | `pg_cron` schedule registered inside a DO block that only runs if the extension is enabled (line 203). If the extension is added *later*, the schedule never gets created. | LOW | Document: "after enabling pg_cron, re-run migration 002 to register the schedule." |
| 6.3.3 | `find_user_by_phone` returns NULL for both "phone not registered" and "phone not in your contacts" (line 143). Callers can't distinguish, which is usually what you want for privacy — but make sure the client code doesn't retry/re-send because of a spurious NULL. | LOW | Confirm caller in `live_location_sharing_service.dart` treats NULL as "SMS path" and stops there. |
| 6.3.4 | `get_live_share` returns `is_active` and `expires_at` even when the share has already ended (line 105-121) — wait, actually it raises `share_ended` before reaching the `RETURN QUERY`, so it's fine. Strike this; no issue. | — | No action. |

### 6.4 — RLS coverage

I only have migrations 001 and 002 in this repo; the baseline `schema.sql` referenced by the comments isn't present under `flutter_app/supabase/`. **I cannot fully verify the baseline RLS posture without it.**

**Recommendation:** check `schema.sql` into the repo under `flutter_app/supabase/migrations/000_initial_schema.sql` (or equivalent) so any future reviewer can see the complete policy set without needing access to the Supabase dashboard. The current state leaves the source of truth off-repo, which is fragile.

Once that file is in-repo, a RLS coverage check table should live here:

```
profiles              RLS: ? policies: ?
emergency_contacts    RLS: ? policies: ?
location_sharing      RLS: ✓ (verified via 002)
location_history      RLS: ? policies: ?
sos_alerts            RLS: ? policies: ?
```

I'll happily do a second pass once `schema.sql` is committed.

---

## 7. Accessibility & Internationalization

### 7.1 — P1 — SOS button has no `Semantics` label · ✅ FIXED

**Problem.** For a safety app, accessibility is not cosmetic: a blind or low-vision user in distress cannot reliably press the SOS button. A user whose hands are shaking or restrained relies on TalkBack/VoiceOver cues. A screen reader on the current home / SOS screen would announce "Button" with no semantic context.

Across the entire `lib/` tree there are only **two `Tooltip`** usages (both in `contacts_screen.dart`) and **zero `Semantics`** widgets.

**Proposed patch for the SOS button:**

```dart
Semantics(
  button: true,
  enabled: true,
  label: 'SOS Emergency Button',
  hint: 'Double tap to start a 5-second countdown. '
        'Long press to send an SOS immediately to your emergency contacts.',
  onTapHint: 'starts the countdown',
  onLongPressHint: 'sends SOS immediately',
  child: GestureDetector(
    onTap: _onTap,
    onLongPress: _onLongPress,
    child: const _SosRedCircle(),
  ),
)
```

Apply the same pattern to:
- Fake-call answer/decline buttons (currently distinguished by color only).
- Location map marker (`Semantics` wrapping the `Marker` child).
- "Stop sharing" button on `active_share_screen.dart`.

**Fix (2026-04-18):** The primary `_SosButton` in `lib/features/sos/screens/sos_screen.dart:170` is now wrapped in `Semantics(button, enabled, label, hint, onTapHint, onLongPressHint, child: GestureDetector(...))`. The announced label is state-aware via a `switch (status)` — e.g. "SOS emergency button" in idle, "SOS countdown, 3 seconds remaining" during the countdown, "Sending SOS alerts" during submission. `onTapHint` and `onLongPressHint` are conditional on the idle state so TalkBack/VoiceOver only advertise the trigger gestures when they're actually available.

The fake-call answer/decline buttons, map marker, and stop-share button remain open for the next accessibility pass.

### 7.2 — P1 — No i18n · ⚠️ DEFERRED

**Problem.** The app is explicitly India-focused (per CLAUDE.md) but has **zero** Hindi or regional-language support. `pubspec.yaml` has `intl: ^0.19.0` but no `flutter_localizations` SDK binding and no `.arb` files.

**Proposed patch:**

1. Add to `pubspec.yaml`:
   ```yaml
   dependencies:
     flutter_localizations:
       sdk: flutter
   flutter:
     generate: true
   ```
2. Add `l10n.yaml` at repo root:
   ```yaml
   arb-dir: lib/l10n
   template-arb-file: app_en.arb
   output-localization-file: app_localizations.dart
   ```
3. Seed `lib/l10n/app_en.arb` and `lib/l10n/app_hi.arb`. Start with the SOS flow (the smallest closed set of strings) so you can ship an end-to-end localized SOS path before localizing the whole app.
4. Configure `MaterialApp` (in `lib/app/app.dart`) with `localizationsDelegates` and `supportedLocales`.

**Prioritize these strings first** (most safety-critical):
- SOS button label, confirmation dialog, countdown.
- Emergency-contacts screen & empty state.
- Location permission rationale.
- "Sharing your live location" foreground-service notification (localized via `flutter_local_notifications` `AndroidNotificationChannel` `name`/`description`).

Regional after Hindi, ordered by India's spoken population: Bengali, Telugu, Tamil, Marathi, Gujarati, Kannada, Malayalam.

**Deferred (2026-04-18):** Scope is broader than a security/hygiene pass. Needs a string audit across every screen plus a product decision on which regional languages ship with v1. Recommended order unchanged: bootstrap `flutter_localizations`, translate the SOS flow first, then broaden.

### 7.3 — Font scaling

Not explicitly tested. A safety app must accommodate users whose device text size is set to maximum (elderly users, low-vision users). Spot-check: set system font size to 200%, confirm no critical control is clipped on the SOS screen.

---

## 8. Prioritized Action List

Status key: ✅ done this pass · ✅/SR done in SECURITY_REVIEW pass · ⚠️ deferred (rationale inline above) · ⏳ not started

### P0 — Ship-blocker (do before any GA launch)

| # | Action | File(s) | Est. effort | Status |
|---|--------|---------|------------:|:------:|
| P0.1 | Encrypt all Hive boxes with an AES cipher rooted in `flutter_secure_storage` (§5.2) | `lib/main.dart`, `lib/core/services/secure_hive.dart`, every `openBox` call | 1.5 days | ✅/SR |
| P0.2 | Move SOS shake detection into the existing background foreground-service isolate so it survives main-isolate death (§4) | `lib/core/services/sos_service.dart`, `lib/core/services/background_service.dart` | 2 days | ⚠️ |
| P0.3 | Minimum test pyramid: `Validators`, `SosNotifier` state machine, `AuthNotifier` hydration, Hive persistence round-trip, SOS countdown widget test (§3.1) | `flutter_app/test/**` | 3 days | ✅ validators only; rest ⚠️ |

### P1 — Pre-launch (should-ship-with)

| # | Action | File(s) | Est. effort | Status |
|---|--------|---------|------------:|:------:|
| P1.1 | `Semantics` labels on SOS, fake-call answer/decline, stop-share, map marker (§7.1) | feature screens | 0.5 day | ✅ SOS button; rest ⏳ |
| P1.2 | Bootstrap i18n with `app_en.arb` + `app_hi.arb`, localize the SOS flow end-to-end (§7.2) | `lib/l10n/`, all screens | 2 days for SOS flow; rest follows | ⚠️ |
| P1.3 | Certificate pinning for Supabase (Android `network_security_config.xml`, iOS TrustKit) plus kill-switch (§5.3) | `android/app/src/main/res/xml/`, `ios/Runner/Info.plist`, Dio interceptor | 1 day | ⚠️/SR |
| P1.4 | Split `HomeScreen` into `BreachWarningBanner`, `IncomingSharesSection`, `QuickActionsGrid`, etc. (§3.3) | `lib/features/home/**` | 1 day | ✅ |
| P1.5 | Split `ContactsNotifier` → `ContactsSyncManager` + thin notifier (§3.2) | `lib/core/providers/contacts_provider.dart`, new `contacts_sync_manager.dart` | 1.5 days | ✅ |
| P1.6 | Introduce `AppRoutes` constants and migrate all call sites (§3.6) | `lib/app/routes.dart`, all screens | 0.5 day | ✅ |

### P2 — Next iteration

| # | Action | File(s) | Status |
|---|--------|---------|:------:|
| P2.1 | Replace `e.toString()` with sealed-class `Failure` types in auth/contacts notifiers, matching the live_sharing pattern (§3.5) | `lib/core/errors/`, `auth_provider.dart`, `contacts_provider.dart` | ⚠️ |
| P2.2 | Wire Crashlytics in `AppLogger.error` for production (§5.6) | `lib/shared/utils/logger.dart` | ⚠️ |
| P2.3 | `BackgroundService.stopSharing()` retry loop + Crashlytics signal for the stuck case (§3.4) | `lib/core/services/background_service.dart` | ✅ retry loop landed; Crashlytics signal awaits P2.2 |
| P2.4 | Wire `firebase_messaging` for live-share recipients (foreground + background handler) | new `lib/core/services/push_service.dart` | ⏳ |
| P2.5 | Persist OTP-resend cooldown across app restarts | `lib/features/auth/screens/unified_auth_screen.dart` | ⏳ |
| P2.6 | Implement password reset (delete the TODOs at `home_screen.dart`, `login_screen.dart`) | auth feature | ⚠️ |
| P2.7 | Implement Audio/Video Recording feature (CLAUDE.md priority #5) or formally deprioritize in the roadmap | new feature | ⏳ |
| P2.8 | Fix `_AuthNotifier` disposal (§3.7) | `lib/app/router.dart` | ✅ |

### INFO / LOW

- `.env.example` warning comment (§5.1). ✅ (landed in SECURITY_REVIEW I-4)
- Commit `schema.sql` into `flutter_app/supabase/migrations/` so the RLS baseline is reviewable in-repo (§6.4). ⏳
- Tighter `analysis_options.yaml` rules (§2.2). ✅
- Evaluate replacing unmaintained `disable_battery_optimization` with in-house code built on `oem_battery_service.dart` (§2.2). ⏳

---

## 9. Positive Observations (Preserve These)

Things that are good today and should not regress:

- **Offline-first bootstrap** — `main.dart:32-52` gracefully continues when Supabase init fails. Good for India's flaky connectivity.
- **`AppLogger` is debug-only** — no PII leakage in production builds.
- **Background isolate is self-contained** — `background_service.dart` re-initializes Supabase in the new isolate, handles the already-initialized case, marks LocationService as background-aware to skip geocoding/Hive writes. Thoughtful.
- **SOS disposal is correct** — `sos_service.dart:237-258` cancels timers, closes controllers defensively, and deliberately does *not* close the shared Hive box. Comment explains why. Nice.
- **Tiered location accuracy** — `normal` / `stationary` / `emergency`. Battery-aware without sacrificing SOS precision.
- **HIBP password-breach check** — `password_breach_service.dart`. Rare to see in a safety app.
- **Supabase migrations explain the *why*** — every non-trivial decision (excluded `address` from public share, 24h cap, REPLICA IDENTITY FULL, dropped is_active filter) has a comment pointing at the specific threat or bug it addresses. This is unusually good.
- **Search-path hardening on all functions** — `001_fix_search_path.sql` is correctly empty-string.
- **`find_user_by_phone` is scoped to caller's own contacts** — prevents mass enumeration.
- **Android permission manifest** — gated by `maxSdkVersion`, `READ_MEDIA_AUDIO` explicitly omitted, `FOREGROUND_SERVICE_LOCATION` present.
- **Consistent `const` constructor use** across widgets.
- **OEM-aware battery handling** (`oem_battery_service.dart`) — Xiaomi/Oppo/Vivo detection + autostart prompt.
- **Discriminated failure types** in `live_sharing_provider.dart` — the model for the rest of the providers to follow.

---

## 10. Appendix

### 10.1 Files inspected directly

- `flutter_app/pubspec.yaml`
- `flutter_app/.env`, `.gitignore`
- `flutter_app/lib/main.dart`
- `flutter_app/lib/app/router.dart`
- `flutter_app/lib/core/providers/auth_provider.dart`
- `flutter_app/lib/core/services/background_service.dart`
- `flutter_app/lib/core/services/sos_service.dart`
- `flutter_app/lib/shared/utils/logger.dart`
- `flutter_app/android/app/src/main/AndroidManifest.xml`
- `flutter_app/supabase/migrations/001_fix_search_path.sql`
- `flutter_app/supabase/migrations/002_live_sharing.sql`
- `flutter_app/test/widget_test.dart`

Line counts verified for: `contacts_provider.dart` (1085), `home_screen.dart` (952), `unified_auth_screen.dart` (790), `location_service.dart` (415), `live_sharing_provider.dart` (381), `validators.dart` (567), `logger.dart` (46).

### 10.2 Files inspected indirectly (via Explore sub-agents)

- `flutter_app/lib/core/services/location_service.dart`
- `flutter_app/lib/core/services/live_location_sharing_service.dart`
- `flutter_app/lib/core/services/auth_service.dart`
- `flutter_app/lib/core/services/contacts_backup_service.dart`
- `flutter_app/lib/core/services/password_breach_service.dart`
- `flutter_app/lib/core/services/sms_service.dart`
- `flutter_app/lib/core/services/oem_battery_service.dart`
- `flutter_app/lib/core/providers/contacts_provider.dart`
- `flutter_app/lib/core/providers/live_sharing_provider.dart`
- `flutter_app/lib/core/providers/sos_provider.dart`
- `flutter_app/lib/features/live_sharing/presentation/screens/active_share_screen.dart`
- `flutter_app/lib/features/live_sharing/presentation/screens/receive_share_screen.dart`
- `flutter_app/lib/features/auth/screens/unified_auth_screen.dart`
- `flutter_app/lib/features/fake_call/screens/fake_call_screen.dart`
- `flutter_app/lib/features/home/screens/home_screen.dart`
- `flutter_app/lib/shared/utils/validators.dart`

### 10.3 Review methodology

1. Three Explore sub-agents ran in parallel to survey architecture, features, and security.
2. Findings were cross-checked by directly reading the files cited above.
3. One initial finding (that `AuthNotifier._safeSetState` was referencing a non-existent `mounted`) was **dropped after verification** — `StateNotifier` does expose `mounted`.
4. One initial CRITICAL finding (leaked Supabase keys in `.env`) was **downgraded to INFO** after confirming `.env` is gitignored, never committed, and the keys in it are public-by-design anon/publishable keys.

### 10.4 Glossary

- **Anon key (Supabase)** — a JWT that identifies requests as coming from the anonymous role. Designed to be shipped to clients. Access is gated by Row-Level Security policies on each table.
- **RLS** — Row-Level Security. PostgreSQL-level policies that filter which rows a given user can SELECT/INSERT/UPDATE/DELETE. The *primary* security boundary in Supabase apps.
- **Isolate (Dart)** — a separate memory space with its own event loop. Cannot share variables with the UI isolate; communicates via messages. Flutter's answer to true background execution.
- **Foreground service (Android)** — a service that posts a user-visible notification and is allowed to run while the app is backgrounded or the screen is locked.
- **E.164** — the international phone-number format, e.g. `+919876543210`.
- **CVE-2018-1058** — Postgres search-path injection. Mitigated by setting `search_path = ''` on all functions, especially `SECURITY DEFINER` ones.

### 10.5 Suggested follow-up agents

Per `CLAUDE.md`:

- `security-reviewer` — run on the encryption + cert-pinning implementations (§5.2, §5.3) once patches land.
- `performance-reviewer` — re-assess `background_service.dart` battery profile after SOS shake detection is moved into the FGS isolate (§P0.2).
- `code-reviewer` — **recommended now** against the `ContactsSyncManager` split and the `HomeScreen` widget extractions (§3.2, §3.3) before anyone builds on top of them.

---

## 11. Remediation Pass Log (2026-04-18)

Changes landed in this branch during the remediation pass, in roughly the order they were applied. Cross-referenced with the finding each change addresses.

| # | Change | File(s) | Finding |
|---|--------|---------|---------|
| 1 | Fix `_AuthNotifier` listener leak; add `ref.onDispose` | `lib/app/router.dart` | §3.7 |
| 2 | `AppRoutes` constants + migrate every live caller | `lib/app/routes.dart` (new), `router.dart`, `main_scaffold.dart`, `home_screen.dart`, `contacts_screen.dart`, `unified_auth_screen.dart`, `active_share_screen.dart`, `start_share_screen.dart` | §3.6 |
| 3 | Enable `unawaited_futures`, `avoid_print`, `prefer_const_*`, `avoid_dynamic_calls`, `use_build_context_synchronously`, `require_trailing_commas`; enable `strict-casts` + `strict-raw-types` | `analysis_options.yaml` | §2.2 |
| 4 | `BackgroundService.stopSharing` now polls `isRunning()` on a [500,1000,2000]-ms back-off and re-invokes `stop` each iteration | `lib/core/services/background_service.dart` | §3.4 |
| 5 | `Semantics(button, label, hint, onTapHint, onLongPressHint)` wrap on the SOS button with state-aware announcements | `lib/features/sos/screens/sos_screen.dart` | §7.1 |
| 6 | Seed validators unit tests: `normalizePhone`, `isValidE164`, `validatePassword`, `containsSqlInjection` | `test/shared/utils/validators_test.dart` (new) | §3.1 |
| 7 | Extract `HomeScreen` into 8 feature widgets (welcome/location/errors/shares/quick actions/dialog/safety tip) | `lib/features/home/widgets/*.dart` (new), `lib/features/home/screens/home_screen.dart` | §3.3 |
| 8 | Extract Supabase I/O into `ContactsSyncManager` (push batch / push one / fetch remote / delete / retry / online probe); notifier now delegates | `lib/core/services/contacts_sync_manager.dart` (new), `lib/core/providers/contacts_provider.dart` | §3.2 |
| 9 | Document all above in this doc with per-finding `Fix (2026-04-18):` blocks and a top-of-document status table | `docs/code-review-2026-04-17.md` | — |

**Build status after the pass:** `flutter analyze` returns 0 errors, 1 pre-existing dead-code warning in `sms_service.dart:103`, and ~135 info-level hints — all of which are cosmetic suggestions surfaced by the newly-enabled stricter lints against pre-existing files; none are regressions introduced here. These are captured as a backlog for a dedicated style-pass diff.
