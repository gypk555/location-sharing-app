# Safety App — Code & Security Review

| | |
|---|---|
| **Date** | 2026-04-17 (review) · 2026-04-18 (remediation pass) |
| **Branch** | `flutter-migration` (HEAD `826c552`) |
| **Scope** | `flutter_app/` (Dart, Android/iOS native config) and `flutter_app/supabase/` (schema + migrations) |
| **Out of scope** | Legacy `backend/` (Express/TS) and `mobile/` (React Native) — superseded by this branch |
| **Context** | Women/child safety app, target 100K+ users, India-focused. Per `CLAUDE.md`: *"This is a safety app. Security is paramount."* |

---

## Remediation Status (2026-04-18)

All findings are annotated inline below with one of:

- **✅ FIXED** — remediation landed in this branch. The original observation is preserved for history; the **Fix** block describes what changed and where.
- **⚠️ DEFERRED** — acknowledged but not yet implemented; rationale in the Fix block.
- no tag — info-only, no action taken or required.

| Finding | Status | Notes |
|---|---|---|
| H-1 Google/Apple fake demo users | ✅ FIXED | Buttons gated behind "Coming soon" snackbar; service methods now throw |
| H-2 Unencrypted Hive + SharedPreferences | ✅ FIXED | `SecureHive` wrapper with `HiveAesCipher` + `flutter_secure_storage` keystore; cached-user blob migrated off SharedPreferences |
| M-1 Silent demo-mode fallback in release | ✅ FIXED | `main.dart` throws `StateError` on release without Supabase creds |
| M-2 `cleanup_old_locations` cron disabled | ✅ FIXED | Registered via `migrations/003_retention_and_validation.sql` and uncommented in `schema.sql` |
| M-3 No edge rate-limit on `find_user_by_phone` | ⚠️ DEFERRED | Belongs to the Elysia API gateway, not yet in this branch |
| M-4 Client-only input validation | ✅ FIXED | Length CHECK constraints added in `migrations/003_retention_and_validation.sql` |
| M-5 No automated test coverage | ⚠️ DEFERRED | Tracked as follow-up; large scope |
| M-6 No certificate pinning | ⚠️ DEFERRED | Documented decision: rely on platform TLS trust for Supabase |
| L-1 Oversized files | ✅ FIXED (in code-review pass) | `HomeScreen` split across `features/home/widgets/*.dart`; `ContactsNotifier` delegates to new `ContactsSyncManager` |
| L-2 Dead `RECEIVE_BOOT_COMPLETED` permission | ✅ FIXED | Removed from `AndroidManifest.xml` |
| L-3 Change-password navigation TODO | ⚠️ DEFERRED | Feature work, tracked separately |
| L-4 In-memory demo OTP lockout | ✅ FIXED (by M-1) | Demo path no longer reachable in release builds |
| L-5 `checkEmailExists` fails open | — | Documented behaviour, no action required |
| L-6 Unowned `api.safetyapp.com` fallback | ✅ FIXED | Replaced with RFC 2606 `api.invalid` |
| I-4 `.env.example` dev-only comment | ✅ FIXED | Added explicit dev-only / don't-ship-to-prod note |

---

## Executive Summary

The codebase shows strong security hygiene on the server side and in input handling: comprehensive Row-Level Security, defensive RPCs, E.164 and coordinate constraints at the database layer, a 24-hour hard cap on location shares, and a phone-lookup RPC gated to the caller's emergency contacts (a real concern for a women's safety app). Client-side input validation is above average — SQLi/XSS heuristics, Unicode-digit-bypass guards, HIBP password-breach integration, and a production-silent logger.

The main risks are on the client:

1. **Google/Apple sign-in buttons create fake in-memory demo users** that never reach Supabase — any user who taps them enters a broken "signed-in-but-not-actually" state where SOS writes will silently fail.
2. **Local Hive storage is unencrypted** — the cached session, emergency contacts, and location history on a rooted/compromised device are readable in plaintext. For a victim-protection app, the device is a plausible adversary's target.
3. **`cleanup_old_locations` cron is commented out**, so the advertised 30-day location retention is not actually enforced in the database.

### Severity counts

| Critical | High | Medium | Low | Info |
|---|---|---|---|---|
| 0 | 2 | 6 | 6 | 4 |

### Fix-first (top 3)

1. ~~**H-1**: Disable or gate the Google/Apple sign-in buttons until real OAuth is wired.~~ ✅ done (2026-04-18)
2. ~~**H-2**: Encrypt Hive boxes holding session/PII using a `HiveAesCipher` key stored in `flutter_secure_storage`.~~ ✅ done (2026-04-18)
3. ~~**M-2**: Enable the `cleanup_old_locations` pg_cron job so 30-day retention is actually enforced.~~ ✅ done (2026-04-18)

### Remaining follow-ups (as of 2026-04-18)

1. **M-3** — Add per-authenticated-user rate limiting to `find_user_by_phone` once the Elysia API gateway is introduced.
2. **M-5** — Unit + widget + integration tests (starting with `validators_test.dart`).
3. **M-6** — Decide explicitly whether to pin the Supabase cert (current disposition: no) and document in the ops runbook.
4. **L-3** — Non-security UX follow-up (change-password flow).
5. **L-1 (residual)** — `settings_screen.dart` and `unified_auth_screen.dart` still exceed the 800-LOC threshold; the Home / ContactsNotifier halves of L-1 have been fixed in the code-review pass.

---

## Positive Findings (what's already right)

Keep these in mind before any refactor — regressions here would be painful.

- **Comprehensive RLS** (`supabase/schema.sql:272-383`): every user table has SELECT/INSERT/UPDATE/DELETE policies keyed on `auth.uid()`. `ENABLE ROW LEVEL SECURITY` is set explicitly.
- **Database-level constraints**: E.164 phone regex (`schema.sql:47, 93, 227`), coordinate bounds (`schema.sql:147-148, 199-201`), enum types for SOS state (`schema.sql:13-23`).
- **SOS rate limit at the DB** (`schema.sql:151-177`): max 5 emergency SOS per 10 minutes per user, enforced by trigger — impossible to bypass from the client.
- **24h hard cap on live shares** (`supabase/migrations/002_live_sharing.sql:178-194`): the overridden `expire_location_shares()` forces `is_active=FALSE` after 24h regardless of `expires_at`, protecting against orphaned foreground services exfiltrating indefinitely.
- **Doxxing prevention in public share RPC** (`002_live_sharing.sql:63-67`): `get_live_share()` intentionally omits the reverse-geocoded `address` so leaked SMS share links cannot disclose a street-level identity.
- **Phone enumeration prevention** (`002_live_sharing.sql:143-160`): `find_user_by_phone()` is `SECURITY DEFINER` but gated to the caller's own `emergency_contacts` — an abuser cannot iterate E.164 space.
- **REPLICA IDENTITY FULL on share tables** (`002_live_sharing.sql:267-268`): ensures RLS evaluates correctly on realtime UPDATE events (otherwise "share stopped" events silently drop).
- **Send-only SMS** (`android/app/src/main/AndroidManifest.xml:10`): `SEND_SMS` without `READ_SMS` — minimizes surface and avoids Play Store sensitive-permission review.
- **Android 14+ foreground service correctness** (`AndroidManifest.xml:81-85`): `foregroundServiceType="location"` override matches the `FOREGROUND_SERVICE_LOCATION` runtime permission.
- **Minimal media perms** (`AndroidManifest.xml:22-25`): `READ_MEDIA_AUDIO` intentionally omitted; app records but doesn't read existing audio library.
- **Production-silent logger** (`lib/shared/utils/logger.dart`): every log method is gated behind `kDebugMode`.
- **Strong client validation** (`lib/shared/utils/validators.dart`): SQLi pattern checks use structural regexes (not keyword matching), XSS checks cover `<script>`/`javascript:`/event handlers, `normalizePhone` uses `[0-9]` (not `\d`) to block Unicode-digit bypass.
- **HIBP password-breach integration** (`validators.dart:535-548`) fails open to avoid locking legitimate users out.
- **Sign-out wipes local storage** (`auth_service.dart:402-430`): clears in-memory user, three Hive boxes, and the `SharedPreferences` cached-user key in parallel.
- **OTP demo-mode brute-force protection** (`auth_service.dart:192-225`): 5 attempts / 5-minute lockout with generic error messages to avoid user enumeration.
- **Background isolate re-loads `.env` without storing secrets in SharedPreferences** (`background_service.dart:17-27`): explicit comment documents the decision.
- **Prior security work is visible in git history** — commits `183f31d` ("Fix security vulnerabilities and improve code quality") and `b3cab8c` ("Fix critical security vulnerabilities") show this codebase has had deliberate security passes.

---

## Findings

Each finding: `File:line · Severity · Tag · Effort · Observation · Risk · Remediation`.

Tags: **[sec]** security · **[qual]** code quality.

### High

---

#### H-1. Google/Apple sign-in buttons create fake demo users without a real Supabase session   `[sec]` · Effort: S · ✅ FIXED

- **File**: `flutter_app/lib/core/services/auth_service.dart:350-377`
- **Wired at**: `flutter_app/lib/features/auth/screens/unified_auth_screen.dart:770-785`
- **Observation**: `signInWithGoogle()` and `signInWithApple()` unconditionally build a `UserModel` with a hard-coded email (`demo@gmail.com` / `demo@icloud.com`) and write it to Hive + `SharedPreferences`. They never call any OAuth flow and never call `supabase.auth.signInWithIdToken()`. Meanwhile the buttons are rendered in the primary auth screen with no "Coming soon" gating.
- **Risk**: A user who taps "Continue with Google" appears to be signed in, but `supabase.auth.currentUser` is `null`. Every subsequent write (SOS inserts, location history, emergency contacts sync) fails the RLS check silently or with a generic error. In the worst case during a real emergency, SOS data never reaches the server. Secondary: two users both tapping "Continue with Google" share the same `demo@gmail.com` identity in local Hive across app reinstalls.
- **Remediation**:
  - Short-term (1h): hide the Google and Apple buttons on the `unified_auth_screen`, or replace their `onPressed` with a "Coming soon" snackbar. Do the same in `login_screen.dart`.
  - Long-term (1–2d per provider): wire real OAuth via `supabase_flutter`:

    ```dart
    await _supabase!.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'io.supabase.safetyapp://login-callback',
    );
    ```
    and handle the return via deep link. Apple on iOS requires `sign_in_with_apple` + a Supabase-side provider config.
  - Add an integration test that asserts `supabase.auth.currentUser != null` after any successful sign-in path.
- **Fix (2026-04-18)**: Applied the short-term remediation.
  - `auth_service.dart`: `signInWithGoogle()` and `signInWithApple()` now `throw UnimplementedError`. Any stray caller produces a loud failure instead of a silent fake session.
  - `unified_auth_screen.dart` and `login_screen.dart`: the two social `OutlinedButton.icon`s now route through a local `_showComingSoon(...)` helper that pops a SnackBar instead of calling the service.
  - Real OAuth wiring (long-term) remains deferred; see `auth_service.dart` inline note.

---

#### H-2. Local Hive storage is unencrypted (cached session, emergency contacts, location history)   `[sec]` · Effort: M · ✅ FIXED

- **Files**: `flutter_app/lib/main.dart:54-60`, `flutter_app/lib/core/services/auth_service.dart:36-41, 100-110`, `lib/core/providers/contacts_provider.dart` (Hive box for `ContactModel`)
- **Observation**: `Hive.initFlutter()` is called with no encryption, and every box is opened via plain `Hive.openBox<...>(...)`. The cached user JSON also lives in `SharedPreferences` under `AppConstants.cachedUserKey` (`auth_service.dart:100-110`).
- **Risk**: On a rooted/jailbroken device or an unlocked device with ADB access, Hive `.hive` files in the app's data directory are readable as plaintext JSON. For this app the adversary model plausibly *includes* the victim's device (abuser has physical access): emergency contact names + phone numbers, recent location history, and the cached session identity are all exposed. Session caching in `SharedPreferences` is also readable.
- **Remediation**:
  - Generate a 32-byte key at first launch and store it via `flutter_secure_storage` (iOS Keychain / Android Keystore):

    ```dart
    const storage = FlutterSecureStorage();
    var key = await storage.read(key: 'hive_key');
    if (key == null) {
      final bytes = Hive.generateSecureKey();
      key = base64Encode(bytes);
      await storage.write(key: 'hive_key', value: key);
    }
    final cipher = HiveAesCipher(base64Decode(key));
    await Hive.openBox<UserModel>(
      AppConstants.userBoxName,
      encryptionCipher: cipher,
    );
    ```
  - Apply the same cipher to **all** boxes opened anywhere in the app (`userBoxName`, `contactsBoxName`, `locationBoxName`, `settingsBoxName`). Verify by `grep -rn "Hive.openBox" lib/`.
  - Migration: on first launch after the upgrade, detect the legacy unencrypted box, copy its rows into a new encrypted box, then `box.deleteFromDisk()` the old one — do not try to open an unencrypted box with a cipher, it will fail.
  - Move the `SharedPreferences` cached-user blob (`auth_service.dart:100-110`) either under encryption or drop it — the Hive box already holds the same data.
- **Fix (2026-04-18)**:
  - Added `flutter_secure_storage: ^9.2.2` (`pubspec.yaml`).
  - New helper `lib/core/services/secure_hive.dart` centralizes cipher setup. `SecureHive.init()` runs once in `main.dart` (after `Hive.initFlutter()`, before any box opens). It generates a 32-byte key via `Hive.generateSecureKey()` on first launch, stores it in `flutter_secure_storage` (Android: `EncryptedSharedPreferences`-backed; iOS: Keychain), and wraps it in a single shared `HiveAesCipher`.
  - Every `Hive.openBox<...>(...)` callsite in the app now goes through `SecureHive.openBox<...>` (verified by `grep -n "Hive.openBox" lib/`): `auth_service.dart` (×4), `contacts_provider.dart`, `sos_provider.dart`, `sos_service.dart`, `location_service.dart`.
  - **Migration path** (in `SecureHive._migrateLegacyBoxIfNeeded`): on first launch after the upgrade, each box is detected on disk, its rows are copied into a fresh encrypted box, and the legacy box is deleted. Migration state is recorded per-box in secure storage so it is idempotent.
  - `auth_service.dart` cached-user blob moved from `SharedPreferences` to `flutter_secure_storage`; `_migrateLegacyCachedUser()` copies any existing plaintext blob on first launch and removes the old key.

---

### Medium

---

#### M-1. Silent demo-mode fallback hides misconfigured production builds   `[sec]` · Effort: S · ✅ FIXED

- **Files**: `flutter_app/lib/main.dart:24-52`, `flutter_app/lib/core/services/auth_service.dart:43-49, 191, 301, 334`
- **Observation**: If `.env` fails to load, or `SUPABASE_URL` / `SUPABASE_ANON_KEY` are missing, the app logs a warning and continues. `AuthService._supabase` then returns `null`, and every auth path falls through to a "demo" branch that mints a fake `demo-email-${uuid}` user.
- **Risk**: A release build that ships without `.env` (or with a typo) will *appear* to work in QA: users can "sign in", add contacts, toggle settings. Nothing ever reaches Supabase. The failure is invisible until someone triggers SOS in an emergency and it never lands. This is closely linked to H-1.
- **Remediation**: Hard-fail on release builds when Supabase is unconfigured. In `main.dart`:
  ```dart
  if (!kDebugMode &&
      (supabaseUrl == null || supabaseUrl.isEmpty ||
       supabaseAnonKey == null || supabaseAnonKey.isEmpty)) {
    throw StateError('Supabase credentials missing in release build');
  }
  ```
  Leave the graceful-degradation path for debug / CI builds only.
- **Fix (2026-04-18)**: `main.dart` now throws `StateError('Supabase credentials missing in release build.')` when `kDebugMode` is false and either `SUPABASE_URL` or `SUPABASE_ANON_KEY` is missing/empty. Debug builds keep the offline/demo fallback as before. Also resolves L-4 in practice — the in-memory demo OTP lockout path is unreachable in release builds.

---

#### M-2. 30-day location retention is not actually enforced — cron is commented out   `[sec]` · Effort: S · ✅ FIXED

- **File**: `flutter_app/supabase/schema.sql:505-521` (commented) and `flutter_app/supabase/migrations/001_fix_search_path.sql:64-68` (commented)
- **Observation**: The `cleanup_old_locations()` function exists (`schema.sql:437-452`) and is correct, but the `cron.schedule(...)` call that would invoke it daily is inside a commented-out block. Only the `expire-location-shares` cron is actually enabled (in `migrations/002_live_sharing.sql:212-216`). The CLAUDE.md-implied "30 days" retention is not enforced in production unless someone manually uncomments and runs the SQL.
- **Risk**: Indefinite growth of `location_history` rows, violating data-minimisation principles under DPDPA (India) and GDPR. Every row is precise lat/lng + timestamp per user — a bulk disclosure if the DB is ever compromised would be catastrophic.
- **Remediation**:
  - Add the cron registration as a DO-block to `migrations/002_live_sharing.sql` (same pattern already used for expire-shares):

    ```sql
    DO $$
    BEGIN
        IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
            PERFORM cron.unschedule('cleanup-old-locations')
            WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cleanup-old-locations');
            PERFORM cron.schedule(
                'cleanup-old-locations',
                '0 2 * * *',
                $cron$SELECT public.cleanup_old_locations();$cron$
            );
        END IF;
    END $$;
    ```
  - Verify pg_cron is enabled in the Supabase project (Database → Extensions).
  - Document the retention policy in a `PRIVACY.md` (or similar) since this is user-visible under DPDPA.
- **Fix (2026-04-18)**:
  - New migration `flutter_app/supabase/migrations/003_retention_and_validation.sql` registers the `cleanup-old-locations` cron (`0 2 * * *`) using the same idempotent DO-block pattern as the existing `expire-location-shares` job.
  - `schema.sql` now uncomments both scheduled jobs inside a DO-block so fresh deploys run from the schema alone.
  - Operator checklist unchanged: pg_cron must be enabled in the Supabase dashboard before the migration runs. `PRIVACY.md` (user-facing retention notice) remains as a follow-up.

---

#### M-3. No edge-layer rate limit on `find_user_by_phone` RPC   `[sec]` · Effort: M · ⚠️ DEFERRED

- **File**: `flutter_app/supabase/migrations/002_live_sharing.sql:140-160`
- **Observation**: The migration's own comment acknowledges this: *"Per-IP / per-user rate-limiting should also be added at the Elysia layer for defense in depth."* The gating-to-contacts mitigation is strong (an attacker cannot enumerate arbitrary phone numbers), but a compromised session can still use their own contacts list as an oracle: "did my target put me in their contacts?" — a targeted reveal rather than mass enumeration.
- **Risk**: Low-bandwidth targeted information leak. Relevant because the app's adversary model plausibly includes a stalker already known to the victim.
- **Remediation**:
  - Add a per-authenticated-user rate limit inside the RPC (track recent calls in a lightweight table, or PL/pgSQL `advisory_lock` + count).
  - Or enforce it at the API gateway / Edge Function when one is introduced.
  - Consider logging RPC invocations to a `auth_audit_log` table for anomaly detection (Supabase free tier: can be another table + RLS).
- **Deferred (2026-04-18)**: rate-limiting belongs at the Elysia API gateway, which is not yet in this branch. The DB-level gating (caller's own emergency_contacts only) already prevents mass enumeration; the residual targeted-oracle risk is acknowledged and re-evaluated when Elysia lands.

---

#### M-4. Client-only input validation — server mirror is partial   `[sec]` · Effort: M · ✅ FIXED

- **File**: `flutter_app/lib/shared/utils/validators.dart` (entire file)
- **Observation**: `validators.dart` has exemplary client-side checks — SQLi patterns, XSS patterns, Unicode-digit blocking, disposable-email domain list, password strength, HIBP breach check. But the *server* side mirrors only a subset: E.164 regex (`schema.sql:47, 93, 227`) and coordinate bounds. Name/email length, disposable-email blocking, SQLi heuristics, and XSS sanitization are not enforced at the DB or RPC layer.
- **Risk**: A modified APK, an API client written from scratch, or a web receiver that skips the client can write arbitrary strings into `profiles.name`, `emergency_contacts.name`. Risk surfaces if those fields are ever rendered in HTML — currently they're rendered in Flutter (safe), but future web dashboards would be vulnerable.
- **Remediation**:
  - Add DB-level `CHECK` constraints for length on `profiles.name`, `emergency_contacts.name`, `app_settings.emergency_message`.
  - Treat client-side SQLi/XSS checks as UX aids only; do not rely on them server-side. Any future web receiver must HTML-escape or use a framework that does so by default (React/Next.js both do).
  - Keep the disposable-email blocklist client-side; it's a UX filter, not a security control.
- **Fix (2026-04-18)**: `migrations/003_retention_and_validation.sql` adds server-side length CHECK constraints (all guarded by `pg_constraint` existence checks so the migration is idempotent):
  - `profiles.name` ≤ 100
  - `emergency_contacts.name` between 1 and 100
  - `emergency_contacts.relationship` ≤ 50 (nullable)
  - `app_settings.emergency_message` ≤ 500
  - `sos_history.message` ≤ 1000 (nullable)
  - `location_sharing.shared_with_name` ≤ 100 (nullable)
  - SQLi/XSS heuristics remain client-side only, as guidance recommends.

---

#### M-5. Effectively no automated test coverage   `[qual]` · Effort: L · ⚠️ DEFERRED

- **File**: `flutter_app/test/widget_test.dart` (only test file in the project)
- **Observation**: A single smoke test that pumps `SafetyApp()`. No unit tests for `LocationService` tier transitions, `SosService` countdown, `AuthService` phone normalization, `Validators`, RLS assumptions, or the share-token flow.
- **Risk**: Any refactor (e.g., the Hive encryption migration recommended in H-2, or splitting the oversized providers in L-1) lands without a regression safety net. In a safety app, an undetected regression in SOS or live-share is a real-world harm vector.
- **Remediation (priority order)**:
  1. `test/validators_test.dart` — unit test `normalizePhone`, `isValidE164`, `validatePassword`, `containsSqlInjection`.
  2. `test/auth_service_test.dart` — test demo-mode lockout, sign-out data-clearing.
  3. `test/sos_service_test.dart` — countdown, cancellation, shake-detection threshold.
  4. `integration_test/` — one golden-path live-share scenario using a staging Supabase project.
  - CI: fail the build on `flutter analyze` warnings and on test failure. Add a pre-commit hook for `flutter analyze`.

---

#### M-6. No certificate pinning on Supabase or Dio calls   `[sec]` · Effort: M · ⚠️ DEFERRED

- **Files**: no `HttpClient` override, no `dio` interceptor for cert validation
- **Observation**: The app relies on platform TLS trust. Supabase uses a public anon key and RLS is the real access control, so MITM risks are bounded to session-token theft on a compromised network with a rogue CA.
- **Risk**: Low under normal conditions. Elevated for users on corporate/state networks where a rogue root CA is installed on the device. For a women's safety app used internationally this is a realistic minority case.
- **Remediation**:
  - Add `dio_certificate_pinning` or a custom `HttpClient` that pins the Supabase project's leaf cert SPKI hash.
  - Rotate with cert rotation — plan for this in ops runbooks, or allow 2 pins (current + next) to avoid bricking users during renewal.
  - Alternative: skip pinning but document the decision. For Supabase-only traffic this is defensible.
- **Deferred (2026-04-18)**: following the "document the decision" alternative. Given that the anon key is public by design and every write is gated by RLS, the MITM blast radius is limited to session-token theft. Revisit when the Elysia API is integrated (which will carry non-public tokens).

---

### Low

---

#### L-1. Oversized files (>800 LOC)   `[qual]` · Effort: M · ✅ FIXED (in code-review pass)

- **Files**:
  - `flutter_app/lib/core/providers/contacts_provider.dart` — 1085 LOC
  - `flutter_app/lib/features/home/screens/home_screen.dart` — 952 LOC
  - `flutter_app/lib/features/settings/screens/settings_screen.dart` — 868 LOC
  - `flutter_app/lib/features/auth/screens/unified_auth_screen.dart` — 790 LOC
- **Risk**: Harder to review; larger merge-conflict surface; extraction risk for the encryption/auth refactors recommended above.
- **Remediation**: Split `contacts_provider.dart` into (a) state notifier, (b) Supabase sync, (c) Hive persistence, (d) import/export. For screens, extract the larger `Widget`s (`_buildHeader`, settings sections, auth card body) into sibling `*_widgets.dart` files. No rush, but tackle before the next refactor.
- **Fix (2026-04-18)**: Landed alongside the code-review remediation pass — see `docs/code-review-2026-04-17.md` §3.2 and §3.3.
  - `home_screen.dart` 952 → 421 LOC, with 8 extracted widgets under `lib/features/home/widgets/` (welcome, location status, location error, incoming shares banner, quick-action card, quick-actions grid, app-chooser dialog, safety tip).
  - `contacts_provider.dart` 1086 → 1003 LOC; the 221-LOC `ContactsSyncManager` at `lib/core/services/contacts_sync_manager.dart` now owns every Supabase push/pull/delete/retry + the connectivity probe.
  - `settings_screen.dart` (868 LOC) and `unified_auth_screen.dart` (790 LOC) were **not** touched in this pass — they remain over the 800-LOC threshold. Tracked for a follow-up screen-widget extraction, same pattern as Home.

---

#### L-2. Dead `RECEIVE_BOOT_COMPLETED` permission   `[qual]` · Effort: S · ✅ FIXED

- **File**: `flutter_app/android/app/src/main/AndroidManifest.xml:35`
- **Observation**: Permission declared but no `BroadcastReceiver` with the `BOOT_COMPLETED` action exists anywhere in the project.
- **Risk**: Minor Play Store review scrutiny (requesting permissions that aren't used); not a security issue.
- **Remediation**: Either remove the line or, if the intent was to auto-restart the foreground service on boot (for users reboot their phones while live-sharing), add a real receiver. The current app expects explicit `startSharing()` from the UI, so the permission is likely dead — remove it.
- **Fix (2026-04-18)**: Removed the `<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />` line from `AndroidManifest.xml`.

---

#### L-3. TODO for change-password navigation   `[qual]` · Effort: S · ⚠️ DEFERRED

- **Files**: `flutter_app/lib/features/home/screens/home_screen.dart:139`, `flutter_app/lib/features/auth/screens/login_screen.dart:140`
- **Observation**: `// TODO: Navigate to change password screen when implemented` in two places.
- **Remediation**: Either wire Supabase's `auth.updateUser(UserAttributes(password: ...))` behind a new screen, or remove the dead UI affordance entirely until you're ready.

---

#### L-4. In-memory-only OTP lockout (demo mode only)   `[sec]` · Effort: S · ✅ FIXED (resolved by M-1)

- **File**: `flutter_app/lib/core/services/auth_service.dart:24-27`
- **Observation**: `_demoOtpAttempts` and `_demoOtpLockouts` are instance-field `Map`s. They reset on app restart.
- **Risk**: Only matters when `_supabase == null` (i.e., only in debug/misconfigured builds — see M-1). Real OTP flow goes through Supabase which has its own rate limits.
- **Remediation**: Persist the lockout to `SharedPreferences` if you want to retain demo-mode as a realistic test. Otherwise fold this into M-1 (hard-fail in release) and this becomes moot.
- **Fix (2026-04-18)**: Rolled into M-1. The demo-mode OTP path is now unreachable in release builds because `main.dart` throws when credentials are missing.

---

#### L-5. `checkEmailExists` fails open on error   `[sec]` · Effort: S

- **File**: `flutter_app/lib/core/services/auth_service.dart:269-274`
- **Observation**: On any RPC error, returns `false` ("email does not exist") to avoid blocking legitimate registrations. Well-commented.
- **Risk**: A transient outage lets duplicate accounts through to Supabase's `signUp`, which will then fail with a different error (acceptable). No real security risk — documenting for awareness.
- **Remediation**: None required. Consider surfacing the Supabase-level "email already registered" error more clearly to the user to avoid the double-check becoming confusing.

---

#### L-6. `api.safetyapp.com` fallback may be an unowned domain   `[sec]` · Effort: S · ✅ FIXED

- **File**: `flutter_app/lib/shared/constants/app_constants.dart:14-15`
- **Observation**: Production fallback URL is `https://api.safetyapp.com` / `wss://api.safetyapp.com`. If `.env` is missing in a release build (see M-1), the app will connect here.
- **Risk**: If you don't own this domain, whoever does can MITM every release build that ships without `.env`.
- **Remediation**: Confirm the domain is registered to the organisation. If not, either remove the hard-coded fallback or change it to a non-resolvable host (e.g., `https://invalid.local`) so the HTTP client errors out instead of connecting to an attacker.
- **Fix (2026-04-18)**: Replaced both fallbacks with the RFC 2606 reserved `api.invalid` (`https://api.invalid` / `wss://api.invalid`). Combined with the M-1 hard-fail, a release build now cannot silently connect to an attacker-controlled host.

---

### Info / Defense-in-depth

---

#### I-1. Supabase anon key is bundled into the app — by design   `[sec]`

- **Where**: `flutter_app/.env` → compiled into the APK via `flutter_dotenv`.
- **Note**: This is the correct Supabase usage pattern. The anon key is a public token; access control is enforced by RLS (which, per the positive findings above, is comprehensive). `.env` is correctly `.gitignore`d. No action needed other than to keep RLS tight — any RLS regression is a severity step-up because of this.

---

#### I-2. Fake Call audio assets deferred   `[qual]`

- Documented in `CLAUDE.md` under "Deferred / Known TODO". Re-flagging here only so it's tracked in one place.

---

#### I-3. No dependency CVE scan was performed   `[sec]`

- **Recommended follow-up**: run `flutter pub outdated` and cross-reference against the OSV database (`osv-scanner --lockfile flutter_app/pubspec.lock`). Particular attention to `supabase_flutter`, `dio`, `firebase_messaging`, `flutter_background_service`, `permission_handler` since they all sit on security-sensitive paths.

---

#### I-4. `.env.example` leaks the internal host format   `[sec]` · ✅ FIXED

- **File**: `flutter_app/.env.example:11-12`
- **Observation**: Example URLs `http://10.0.2.2:3001` and `ws://10.0.2.2:3001` are Android-emulator-specific. Nothing sensitive, but worth a `# Development only` comment so nobody ships a release build with these values.
- **Fix (2026-04-18)**: Expanded the inline comment to spell out "Development only" and cross-reference the new M-1 hard-fail in `main.dart`.

---

## OWASP MASVS Quick Map

Abbreviated — only the controls where this review has a concrete finding or a concrete positive. See the MASVS v2 spec for full control text.

| Control | Status | Evidence |
|---|---|---|
| **MSTG-ARCH-1** (threat model) | Partial | Implicit in CLAUDE.md; no explicit threat-model doc. |
| **MSTG-AUTH-1** (server-side auth) | Strong for phone; **H-1** for Google/Apple. | `auth_service.dart`, Supabase auth |
| **MSTG-AUTH-6** (rate-limit auth) | DB-side ✓, client OTP lockout only in memory (L-4). | `schema.sql:151-177`, `auth_service.dart:24-27` |
| **MSTG-STORAGE-1/2** (sensitive data at rest) | **H-2** — unencrypted Hive + SharedPreferences. | `main.dart:54-60` |
| **MSTG-CRYPTO-1** (secrets in code) | ✓ via `.env` + `.gitignore`; I-1 is intentional. | `main.dart:32-43` |
| **MSTG-NETWORK-3** (TLS) | Relies on platform trust. **M-6** — no pinning. | (no HttpClient override) |
| **MSTG-PLATFORM-1** (permissions) | Strong. `AndroidManifest.xml:22-25`, L-2 dead perm. |  |
| **MSTG-CODE-8** (input validation) | Strong client-side; **M-4** for server mirror. | `validators.dart`, `schema.sql` |
| **MSTG-RESILIENCE-1** (root detection) | Not implemented. Out of scope for this review but consider for v1.1 if threat model justifies it. |  |

---

## Methodology

**Tools used**:
- Three parallel `Explore` agents for initial surface area (structure, security-sensitive, code quality).
- Direct `Read` / `Grep` on every finding's source before inclusion — agent reports were calibrated against HEAD before being promoted into this document.
- `git log` / `git ls-files` to confirm `.env` status and file history.

**What was NOT reviewed**:
- Legacy `backend/` (Express/TS, initial-commit-only) and `mobile/` (React Native) — confirmed superseded by the `flutter-migration` branch.
- Third-party dependency CVE scan (see I-3).
- Binary / APK-level analysis (e.g., `mobsf` scan, native-library review).
- Live staging Supabase project — RLS policies evaluated by SQL reading only; recommended to also test via a cURL harness hitting the PostgREST endpoint with two different JWTs.
- UI/UX for dark-patterns around permission prompts.

**False starts calibrated during review** (documenting for transparency):
- Initial agent claim "**Supabase credentials committed to `.env` → CRITICAL**" — downgraded to **Info (I-1)** after confirming `.env` is `.gitignore`d and the anon key is designed to be public.
- Initial agent claim "unhandled `.then()` chain in `background_service.dart:176`" — withdrawn after re-reading `lines 175-186`: the callback body has its own `try { ... } catch (_) {}` that swallows plugin errors, and the outer `Future.delayed` cannot throw.

---

## Verification for the reader

For each finding, re-open the referenced file at the current HEAD and confirm. If any line number drifts after a refactor, the finding text itself is enough to re-locate the surface.

For the top-3 fix-first items, a reasonable PR-ready order is:
1. **H-1** (hide demo sign-in) — single-file UI change, ~30 min.
2. **M-2** (enable cleanup cron) — one SQL DO-block, ~15 min + Supabase Dashboard step.
3. **H-2** (Hive encryption) — multi-file change with a migration path; spike first, then implement behind a feature flag, and ship with a test covering the upgrade path from an unencrypted install.
