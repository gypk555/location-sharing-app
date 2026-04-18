import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/utils/logger.dart';
import '../models/contact_model.dart';
import '../services/live_location_sharing_service.dart';

/// Singleton service provider — the service is a stateless singleton so
/// this is just a thin Riverpod handle for dependency injection + testing.
final liveLocationSharingServiceProvider =
    Provider<LiveLocationSharingService>(
  (ref) => LiveLocationSharingService(),
);

/// Snapshot of the sharer's currently-active session (if any). This is
/// what the UI binds to for the "Active Share" screen.
class LiveSharingState {
  final String? sessionGroupId;
  final List<SharedRecipient> recipients;
  final bool isStarting;
  final String? error;
  final bool isSosTriggered;

  /// True when the current session was loaded from the server on app
  /// startup (not started this run). The active-share screen uses this
  /// to show an info banner explaining the session was already running.
  final bool isHydrated;

  /// When the session will auto-expire. Null means indefinite
  /// ("Until I stop" or SOS). Drives the client-side expiry timer.
  final DateTime? expiresAt;

  const LiveSharingState({
    this.sessionGroupId,
    this.recipients = const [],
    this.isStarting = false,
    this.error,
    this.isSosTriggered = false,
    this.isHydrated = false,
    this.expiresAt,
  });

  bool get isActive => sessionGroupId != null;

  /// Whether the session has already passed its expiry time.
  bool get isExpired {
    final ea = expiresAt;
    if (ea == null) return false;
    return DateTime.now().toUtc().isAfter(ea);
  }

  /// Remaining time until expiry. Null if indefinite, negative if past.
  Duration? get remainingUntilExpiry {
    final ea = expiresAt;
    if (ea == null) return null;
    return ea.difference(DateTime.now().toUtc());
  }

  LiveSharingState copyWith({
    String? sessionGroupId,
    List<SharedRecipient>? recipients,
    bool? isStarting,
    Object? error = _sentinel,
    bool? isSosTriggered,
    bool? isHydrated,
    DateTime? expiresAt,
  }) {
    return LiveSharingState(
      sessionGroupId: sessionGroupId ?? this.sessionGroupId,
      recipients: recipients ?? this.recipients,
      isStarting: isStarting ?? this.isStarting,
      error: identical(error, _sentinel) ? this.error : error as String?,
      isSosTriggered: isSosTriggered ?? this.isSosTriggered,
      isHydrated: isHydrated ?? this.isHydrated,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  LiveSharingState cleared() {
    return const LiveSharingState();
  }

  static const _sentinel = Object();
}

class LiveSharingNotifier extends StateNotifier<LiveSharingState> {
  LiveSharingNotifier(this._service) : super(const LiveSharingState());

  final LiveLocationSharingService _service;

  /// How often to re-check the server while a session is active, to
  /// catch DB-side expiries (cron job) or stops from other devices.
  /// Dart `Timer`s run on the UI isolate event loop, which stops when
  /// the app is backgrounded — [_pollTimer] is the *foreground* sync
  /// path; background → foreground is handled by lifecycle resume.
  // The Realtime subscription in `incomingSharesProvider` is the
  // primary change-notification channel; the poll is just a safety net
  // for cases where Realtime drops silently. Bumped from 15s to 60s to
  // match the heartbeat cadence and cut foreground SELECTs 4x.
  static const _pollInterval = Duration(seconds: 60);

  /// Timer that fires when the current session reaches its expiry time.
  /// Cancelled on stop() and reset on every state change that has a new
  /// expiresAt. Dart Timers don't fire while the app is backgrounded —
  /// that case is handled by [hydrateFromServer] on app resume.
  Timer? _expiryTimer;

  /// Periodic poll that re-syncs state from the server while a session
  /// is active. Catches DB-driven changes the client-side [_expiryTimer]
  /// can't see (e.g. cron flipping is_active, admin UPDATE, another
  /// device stopping the session).
  Timer? _pollTimer;

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  /// Schedule [_handleExpiry] to fire at the current state's expiresAt.
  /// If expiresAt is null (indefinite), cancels any existing timer.
  /// If expiresAt is already past, fires immediately.
  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    _expiryTimer = null;

    final expiresAt = state.expiresAt;
    if (expiresAt == null || !state.isActive) return;

    final remaining = expiresAt.difference(DateTime.now().toUtc());
    if (remaining.isNegative || remaining == Duration.zero) {
      // Already expired — fire on the next microtask so we don't mutate
      // state during a setter call.
      Future.microtask(_handleExpiry);
      return;
    }
    _expiryTimer = Timer(remaining, _handleExpiry);
  }

  /// Start the foreground poll if a session is active and no timer is
  /// running. Idempotent.
  void _startPolling() {
    if (_pollTimer != null && _pollTimer!.isActive) return;
    if (!state.isActive) return;
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (!state.isActive) {
        _pollTimer?.cancel();
        _pollTimer = null;
        return;
      }
      // Fire and forget; hydrateFromServer is idempotent and clears
      // state if the server says there's nothing active.
      hydrateFromServer();
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _handleExpiry() async {
    if (!state.isActive) return;
    AppLogger.info('live-sharing: session expired, stopping');
    await stop();
  }

  Future<bool> startManual({
    required List<ContactModel> contacts,
    required ShareDuration duration,
  }) async {
    state = state.copyWith(isStarting: true, error: null);
    final outcome = await _service.startManualSharing(
      contacts: contacts,
      duration: duration,
    );
    if (!outcome.isSuccess) {
      state = state.copyWith(
        isStarting: false,
        error: _messageForFailure(outcome.failure!),
      );
      return false;
    }
    final result = outcome.result!;
    state = LiveSharingState(
      sessionGroupId: result.sessionGroupId,
      recipients: result.recipients,
      isStarting: false,
      isSosTriggered: false,
      expiresAt: result.expiresAt,
    );
    _scheduleExpiry();
    _startPolling();
    return true;
  }

  Future<bool> startFromSos(List<ContactModel> contacts) async {
    state = state.copyWith(isStarting: true, error: null);
    final outcome = await _service.autoStartFromSos(contacts);
    if (!outcome.isSuccess) {
      state = state.copyWith(
        isStarting: false,
        error: _messageForFailure(outcome.failure!),
      );
      return false;
    }
    final result = outcome.result!;
    state = LiveSharingState(
      sessionGroupId: result.sessionGroupId,
      recipients: result.recipients,
      isStarting: false,
      isSosTriggered: true,
      expiresAt: result.expiresAt,
    );
    _scheduleExpiry();
    _startPolling();
    return true;
  }

  Future<void> stop() async {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _stopPolling();
    final id = state.sessionGroupId;
    if (id == null) return;
    await _service.stopSession(id);
    state = state.cleared();
  }

  Future<void> stopRecipient(String sharingRowId) async {
    await _service.stopRecipient(sharingRowId);
    final updated =
        state.recipients.where((r) => r.sharingRowId != sharingRowId).toList();
    if (updated.isEmpty) {
      // No recipients left — tear the whole session down.
      await stop();
    } else {
      state = state.copyWith(recipients: updated);
    }
  }

  /// Check Supabase for any active sharing sessions owned by the current
  /// user and rebuild [state] from them. Called on app launch, on app
  /// resume from background (via MainScaffold lifecycle observer), and
  /// anywhere else where the UI may be out of sync with the DB.
  ///
  /// If the server says there's no active session but we have local
  /// in-memory state, the local state is cleared — this is how an
  /// expired session gets reflected in the UI when the user comes back
  /// from a long background where the Dart expiry timer didn't fire.
  /// Re-entrancy guard: a slow poll (15s+) can stack up if the network
  /// is sluggish, causing multiple concurrent SELECTs and overlapping
  /// state writes. A single in-flight hydration is plenty.
  bool _isHydrating = false;

  Future<void> hydrateFromServer() async {
    if (_isHydrating) return;
    _isHydrating = true;
    try {
      final rows = await _service.activeSessions();
      if (rows.isEmpty) {
        if (state.isActive) {
          // Server has no active sessions but we thought we had one —
          // cron expired it, another device stopped it, or the user's
          // session went stale. Mirror the server: clear state + stop
          // any running background service.
          _expiryTimer?.cancel();
          _expiryTimer = null;
          _stopPolling();
          // Fire-and-forget stopSession to make sure the background
          // service is torn down. It's safe if the rows are already
          // is_active=false — the update is a no-op but stopSharing()
          // stops the foreground service.
          final id = state.sessionGroupId;
          if (id != null) {
            unawaited(_service.stopSession(id));
          }
          state = state.cleared();
        }
        return;
      }

      // Group by session_group_id; pick the group with the newest
      // created_at. In normal flows there's exactly one.
      final grouped = <String, List<Map<String, dynamic>>>{};
      for (final row in rows) {
        final gid = (row['session_group_id'] as String?) ?? '';
        if (gid.isEmpty) continue;
        grouped.putIfAbsent(gid, () => []).add(row);
      }
      if (grouped.isEmpty) return;

      final sortedGroups = grouped.entries.toList()
        ..sort((a, b) {
          final aCreated = DateTime.parse(a.value.first['created_at'] as String);
          final bCreated = DateTime.parse(b.value.first['created_at'] as String);
          return bCreated.compareTo(aCreated);
        });
      final newestGroup = sortedGroups.first;
      final groupId = newestGroup.key;
      final groupRows = newestGroup.value;

      final recipients = groupRows.map((row) {
        final token = row['share_token'] as String;
        return SharedRecipient(
          sharingRowId: row['id'] as String,
          shareToken: token,
          name: (row['shared_with_name'] as String?) ?? 'Contact',
          phone: (row['shared_with_phone'] as String?) ?? '',
          resolvedUserId: row['shared_with_id'] as String?,
          publicUrl: _service.publicUrlForToken(token),
        );
      }).toList();

      final isSos = groupRows.any(
        (row) => (row['trigger_source'] as String?) == 'sos',
      );

      // All rows in a group share the same expires_at.
      final expiresAtStr = groupRows.first['expires_at'] as String?;
      final expiresAt = expiresAtStr != null
          ? DateTime.parse(expiresAtStr).toUtc()
          : null;

      state = LiveSharingState(
        sessionGroupId: groupId,
        recipients: recipients,
        isStarting: false,
        isSosTriggered: isSos,
        isHydrated: true,
        expiresAt: expiresAt,
      );

      // Re-schedule the client-side expiry timer based on the server's
      // truth. If the session has already expired and the cron hasn't
      // run yet, _scheduleExpiry will fire immediately and stop() will
      // cascade down to the background service.
      _scheduleExpiry();
      // Keep the foreground poll going so subsequent server-side
      // changes (cron expiry, admin UPDATE, remote stop) propagate.
      _startPolling();

      AppLogger.info(
        'live-sharing: hydrated session $groupId with '
        '${recipients.length} recipient(s) from server',
      );
    } catch (e, stack) {
      AppLogger.error('hydrateFromServer failed', e, stack);
    } finally {
      _isHydrating = false;
    }
  }

  String _messageForFailure(StartShareFailure failure) {
    switch (failure) {
      case AuthFailure(:final message):
        return message;
      case DatabaseFailure(:final code, :final message):
        // Raw PostgREST / Postgres error text can leak constraint names,
        // column names, and function signatures. Log the raw at error
        // level (the service layer already does this) and return a
        // generic user-facing string for anything we don't have a
        // specific translation for.
        AppLogger.debug('live-sharing DB failure $code: $message');
        if (code == '23505') {
          return 'A previous share with one of these contacts is still '
              'active. Try again in a moment.';
        }
        return 'Could not start live sharing. Please try again.';
      case UnknownFailure():
        return 'Could not start live sharing. Please try again.';
    }
  }
}

final liveSharingProvider =
    StateNotifierProvider<LiveSharingNotifier, LiveSharingState>((ref) {
  return LiveSharingNotifier(ref.watch(liveLocationSharingServiceProvider));
});
