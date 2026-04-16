import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../shared/utils/logger.dart';
import '../models/contact_model.dart';
import 'background_service.dart';
import 'location_service.dart';

/// Result of a share-start attempt. Carries the session id so callers can
/// immediately navigate to the active-session screen and so they can
/// distribute the per-recipient URLs to unregistered contacts.
class StartShareResult {
  final String sessionGroupId;
  final List<SharedRecipient> recipients;

  /// When this session will auto-expire. Null means indefinite
  /// (e.g. SOS auto-start, or the user picked "Until I stop").
  final DateTime? expiresAt;

  StartShareResult({
    required this.sessionGroupId,
    required this.recipients,
    this.expiresAt,
  });
}

/// Typed failure reasons returned by the share-start flow. Lets the UI
/// layer show a meaningful message instead of a generic "check your
/// connection" catch-all.
sealed class StartShareFailure {
  const StartShareFailure();
}

/// Auth token expired or user is no longer signed in. UI should prompt
/// for re-auth.
class AuthFailure extends StartShareFailure {
  final String message;
  const AuthFailure([this.message = 'Your session expired. Please sign in again.']);
}

/// Any Postgres error. [code] is the PostgREST error code (e.g. '23505'
/// for unique violation), [message] is the raw DB message — useful to
/// surface to the user during development and for diagnosing edge cases.
class DatabaseFailure extends StartShareFailure {
  final String? code;
  final String message;
  const DatabaseFailure(this.code, this.message);
}

/// Anything else — network, serialization, unexpected shape.
class UnknownFailure extends StartShareFailure {
  final String message;
  const UnknownFailure(this.message);
}

/// Success + failure discriminated return from start-share operations.
class StartShareOutcome {
  final StartShareResult? result;
  final StartShareFailure? failure;
  const StartShareOutcome._(this.result, this.failure);

  factory StartShareOutcome.success(StartShareResult r) =>
      StartShareOutcome._(r, null);
  factory StartShareOutcome.fail(StartShareFailure f) =>
      StartShareOutcome._(null, f);

  bool get isSuccess => result != null;
}

/// One row in location_sharing + its derived public URL.
class SharedRecipient {
  final String sharingRowId;
  final String shareToken;
  final String name;
  final String phone;
  final String? resolvedUserId;
  final String publicUrl;

  SharedRecipient({
    required this.sharingRowId,
    required this.shareToken,
    required this.name,
    required this.phone,
    required this.resolvedUserId,
    required this.publicUrl,
  });

  /// Whether this recipient is a registered app user (will get in-app
  /// realtime updates + FCM push). If false, they'll only see the location
  /// via the public web page at [publicUrl].
  bool get isRegistered => resolvedUserId != null;
}

/// Duration options for a live-sharing session. `null` means indefinite
/// (used for SOS).
enum ShareDuration {
  fifteenMinutes,
  oneHour,
  eightHours,
  untilStopped;

  int? get minutes {
    switch (this) {
      case ShareDuration.fifteenMinutes:
        return 15;
      case ShareDuration.oneHour:
        return 60;
      case ShareDuration.eightHours:
        return 60 * 8;
      case ShareDuration.untilStopped:
        return null;
    }
  }
}

/// Core service that manages the live-location-sharing lifecycle:
///   - start manual / SOS share sessions (writes to location_sharing)
///   - resolve contacts to registered users (via find_user_by_phone RPC)
///   - build the public web URL for each recipient
///   - start/stop the background service
///   - stop a session or a single recipient
///
/// This service runs in the UI isolate. The per-position writes to
/// location_history are owned by the background isolate in background_service.dart.
class LiveLocationSharingService {
  static final LiveLocationSharingService _instance =
      LiveLocationSharingService._internal();
  factory LiveLocationSharingService() => _instance;
  LiveLocationSharingService._internal();

  static const _uuid = Uuid();

  SupabaseClient get _supabase => Supabase.instance.client;

  /// Build the public URL for a share token. Points to the live-share
  /// Edge Function which returns an HTML page that polls get_live_share.
  /// Safe to call even when the Edge Function isn't deployed yet — the
  /// URL just 404s in that case. Public so callers that reconstruct a
  /// [SharedRecipient] from a raw DB row can derive the same URL.
  String publicUrlForToken(String token) {
    final base = _supabase.rest.url.replaceFirst('/rest/v1', '');
    return '$base/functions/v1/live-share/$token';
  }

  /// Resolve a phone to a registered user id via find_user_by_phone RPC.
  /// Returns null if not registered or on error.
  Future<String?> resolveUserId(String phone) async {
    try {
      final result = await _supabase.rpc(
        'find_user_by_phone',
        params: {'p_phone': phone},
      );
      if (result == null) return null;
      return result.toString();
    } catch (e) {
      AppLogger.error('find_user_by_phone failed for $phone', e);
      return null;
    }
  }

  /// Start a manual time-boxed share session.
  ///
  /// Inserts one `location_sharing` row per contact, all sharing the same
  /// `session_group_id`. Resolves each contact to a registered user id
  /// via RPC before insert. Starts the background service and begins
  /// position streaming at the normal tier.
  Future<StartShareOutcome> startManualSharing({
    required List<ContactModel> contacts,
    required ShareDuration duration,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      AppLogger.warning('startManualSharing: no current user');
      return StartShareOutcome.fail(
        const AuthFailure('You must be signed in to share your live location.'),
      );
    }
    if (contacts.isEmpty) {
      AppLogger.warning('startManualSharing: no contacts');
      return StartShareOutcome.fail(
        const UnknownFailure('Please select at least one contact.'),
      );
    }

    final sessionGroupId = _uuid.v4();
    final now = DateTime.now().toUtc();
    final expiresAt = duration.minutes == null
        ? null
        : now.add(Duration(minutes: duration.minutes!));

    return _createSession(
      ownerId: user.id,
      contacts: contacts,
      sessionGroupId: sessionGroupId,
      expiresAt: expiresAt,
      triggerSource: 'manual',
      initialTier: TrackingTier.normal,
      durationMinutes: duration.minutes,
    );
  }

  /// Start an indefinite share session for all SOS contacts. Called from
  /// SosService.trigger() after the one-shot SMS send. Bumps tier to
  /// emergency (5s cadence).
  Future<StartShareOutcome> autoStartFromSos(
      List<ContactModel> contacts) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      return StartShareOutcome.fail(const AuthFailure());
    }
    if (contacts.isEmpty) {
      return StartShareOutcome.fail(
        const UnknownFailure('No SOS contacts configured.'),
      );
    }

    final sessionGroupId = _uuid.v4();
    return _createSession(
      ownerId: user.id,
      contacts: contacts,
      sessionGroupId: sessionGroupId,
      expiresAt: null,
      triggerSource: 'sos',
      initialTier: TrackingTier.emergency,
      durationMinutes: null,
    );
  }

  /// Refresh the Supabase auth session if it's expired or about to expire.
  /// Returns null on success, or an [AuthFailure] if the refresh failed.
  Future<AuthFailure?> _ensureFreshSession() async {
    final session = _supabase.auth.currentSession;
    if (session == null) return const AuthFailure();
    // `isExpired` is true only AFTER the JWT has expired. For safety,
    // also refresh within 60 seconds of the expiry to avoid races.
    final expiresAt = session.expiresAt;
    final nowSec = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final aboutToExpire =
        expiresAt != null && expiresAt - nowSec < 60;
    if (session.isExpired || aboutToExpire) {
      try {
        await _supabase.auth.refreshSession();
      } on AuthException catch (e) {
        AppLogger.error('session refresh failed: ${e.message}', e);
        return AuthFailure('Your session expired: ${e.message}');
      } catch (e) {
        AppLogger.error('session refresh failed (unknown)', e);
        return const AuthFailure();
      }
    }
    return null;
  }

  /// Deactivate any pre-existing active rows for the same owner that
  /// target any of the given recipients. This prevents the
  /// `idx_location_sharing_unique_active` index from rejecting our
  /// INSERT when a previous session was never explicitly stopped.
  ///
  /// Runs as two UPDATEs (one for resolved user IDs, one for phone-only
  /// recipients). Not strictly transactional, but safe for the
  /// single-user case — no concurrent writes for the same owner.
  Future<void> _deactivateExistingRows({
    required String ownerId,
    required List<String> resolvedUserIds,
    required List<String> phoneNumbers,
  }) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    try {
      if (resolvedUserIds.isNotEmpty) {
        await _supabase
            .from('location_sharing')
            .update({'is_active': false, 'revoked_at': nowIso})
            .eq('owner_id', ownerId)
            .eq('is_active', true)
            .inFilter('shared_with_id', resolvedUserIds);
      }
      if (phoneNumbers.isNotEmpty) {
        await _supabase
            .from('location_sharing')
            .update({'is_active': false, 'revoked_at': nowIso})
            .eq('owner_id', ownerId)
            .eq('is_active', true)
            .inFilter('shared_with_phone', phoneNumbers);
      }
    } catch (e, stack) {
      // Non-fatal: if the pre-cleanup fails, the subsequent insert will
      // surface the real error via the unique constraint. We still log.
      AppLogger.error('live-sharing: pre-deactivate failed', e, stack);
    }
  }

  Future<StartShareOutcome> _createSession({
    required String ownerId,
    required List<ContactModel> contacts,
    required String sessionGroupId,
    required DateTime? expiresAt,
    required String triggerSource,
    required TrackingTier initialTier,
    required int? durationMinutes,
  }) async {
    // 0. Request the runtime POST_NOTIFICATIONS permission up front. The
    // foreground service needs it to post its persistent notification on
    // Android 13+; without it Android kills the process with
    // CannotPostForegroundServiceNotificationException. Must happen BEFORE
    // any DB writes so a denial doesn't leave orphaned active rows.
    final notifGranted = await BackgroundService.ensureNotificationPermission();
    if (!notifGranted) {
      return StartShareOutcome.fail(const UnknownFailure(
        'Notifications are required to run live sharing in the background. '
        'Please enable notifications for Safety App in system settings.',
      ));
    }

    // 1. Defensively refresh the JWT if it's expired.
    final authFail = await _ensureFreshSession();
    if (authFail != null) {
      return StartShareOutcome.fail(authFail);
    }

    // 2. Resolve each contact to a registered user id in parallel. If
    // resolved, we set shared_with_id and leave shared_with_phone null.
    // If not, we only set shared_with_phone. Both columns are nullable.
    final rowsFutures = contacts.map((c) async {
      final resolved = await resolveUserId(c.phone);
      return <String, dynamic>{
        'owner_id': ownerId,
        'shared_with_id': resolved,
        'shared_with_phone': resolved == null ? c.phone : null,
        'shared_with_name': c.name,
        'session_group_id': sessionGroupId,
        'trigger_source': triggerSource,
        'is_active': true,
        'share_duration_minutes': durationMinutes,
        'expires_at': expiresAt?.toIso8601String(),
      };
    });
    final rows = await Future.wait(rowsFutures);

    // 3. Deactivate any pre-existing active rows targeting the same
    // recipients. This is the fix for the "Could not start live sharing"
    // bug — without this, the unique active-share index rejects the
    // INSERT when a previous session was never stopped.
    final resolvedIds = rows
        .map((r) => r['shared_with_id'] as String?)
        .whereType<String>()
        .toList();
    final phones = rows
        .map((r) => r['shared_with_phone'] as String?)
        .whereType<String>()
        .toList();
    await _deactivateExistingRows(
      ownerId: ownerId,
      resolvedUserIds: resolvedIds,
      phoneNumbers: phones,
    );

    // 4. Insert the new session rows.
    List<Map<String, dynamic>> inserted;
    try {
      inserted = await _supabase
          .from('location_sharing')
          .insert(rows)
          .select();
    } on AuthException catch (e, stack) {
      AppLogger.error('live-sharing: auth error on insert', e, stack);
      return StartShareOutcome.fail(AuthFailure(e.message));
    } on PostgrestException catch (e, stack) {
      AppLogger.error(
          'live-sharing: postgrest ${e.code}: ${e.message}', e, stack);
      return StartShareOutcome.fail(DatabaseFailure(e.code, e.message));
    } catch (e, stack) {
      AppLogger.error('live-sharing: unknown insert failure', e, stack);
      return StartShareOutcome.fail(UnknownFailure(e.toString()));
    }

    // 5. Build typed recipients with public URLs.
    final recipients = <SharedRecipient>[];
    for (var i = 0; i < inserted.length; i++) {
      final row = inserted[i];
      final contact = contacts[i];
      final token = row['share_token'] as String;
      recipients.add(SharedRecipient(
        sharingRowId: row['id'] as String,
        shareToken: token,
        name: contact.name,
        phone: contact.phone,
        resolvedUserId: row['shared_with_id'] as String?,
        publicUrl: publicUrlForToken(token),
      ));
    }

    // 6. Start the background location service with the requested tier.
    final bgStarted = await BackgroundService.startSharing(
      sessionGroupId: sessionGroupId,
      recipientCount: recipients.length,
      initialTier: initialTier,
    );
    if (!bgStarted) {
      // Foreground service refused to start (typically notification perm
      // revoked between pre-check and now). Roll back the rows we inserted
      // so we don't leave an orphaned active session in the DB.
      await stopSession(sessionGroupId);
      return StartShareOutcome.fail(const UnknownFailure(
        'Could not start the background sharing service. '
        'Check notification permissions and try again.',
      ));
    }

    AppLogger.info(
      'live-sharing: started $triggerSource session $sessionGroupId '
      'with ${recipients.length} recipient(s)',
    );

    return StartShareOutcome.success(StartShareResult(
      sessionGroupId: sessionGroupId,
      recipients: recipients,
      expiresAt: expiresAt,
    ));
  }

  /// Stop all recipients of a given session. Bulk-marks rows inactive +
  /// revoked, then stops the background service. Idempotent.
  Future<void> stopSession(String sessionGroupId) async {
    try {
      await _supabase
          .from('location_sharing')
          .update({
            'is_active': false,
            'revoked_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('session_group_id', sessionGroupId)
          .eq('is_active', true);
    } catch (e) {
      AppLogger.error('stopSession update failed', e);
    }

    // Check if any other active session exists before stopping the
    // background service. A user could be in an SOS session while also
    // having a manual session running.
    try {
      final remaining = await _supabase
          .from('location_sharing')
          .select('id')
          .eq('owner_id', _supabase.auth.currentUser?.id ?? '')
          .eq('is_active', true)
          .limit(1);
      if ((remaining as List).isEmpty) {
        await BackgroundService.stopSharing();
      }
    } catch (e) {
      AppLogger.error('stopSession remaining check failed', e);
      // Fail-safe: stop the service anyway
      await BackgroundService.stopSharing();
    }
  }

  /// Stop a single recipient without affecting others in the same session.
  Future<void> stopRecipient(String sharingRowId) async {
    try {
      await _supabase
          .from('location_sharing')
          .update({
            'is_active': false,
            'revoked_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', sharingRowId);
    } catch (e) {
      AppLogger.error('stopRecipient failed', e);
    }
  }

  /// Fetch the current user's active share sessions (one row per recipient).
  /// Caller can group by session_group_id for UI rendering.
  Future<List<Map<String, dynamic>>> activeSessions() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return const [];
    try {
      final rows = await _supabase
          .from('location_sharing')
          .select()
          .eq('owner_id', user.id)
          .eq('is_active', true)
          .order('created_at', ascending: false);
      return (rows as List).cast<Map<String, dynamic>>();
    } catch (e) {
      AppLogger.error('activeSessions query failed', e);
      return const [];
    }
  }
}
