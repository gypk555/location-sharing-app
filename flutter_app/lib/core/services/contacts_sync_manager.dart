import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/utils/logger.dart';
import '../models/contact_model.dart';

/// Outcome of a single-contact push. Reported back to the caller so the
/// notifier can flip `isSynced` on the local copy (and update Hive under
/// its mutex).
enum PushOutcome { success, failure }

/// Outcome of a pull: merged list + counts for logging/telemetry.
class PullResult {
  final List<ContactModel> remoteContacts;
  final int fetchedCount;
  PullResult({required this.remoteContacts, required this.fetchedCount});
}

/// Owns every Supabase-specific read/write for emergency contacts
/// (push, pull, delete, retry, batch-push) along with the connectivity
/// probe used to short-circuit sync when offline.
///
/// Extracted from `ContactsNotifier` (code-review finding §3.2) so that
/// the notifier stays focused on Hive persistence + state orchestration.
/// The notifier owns the Hive mutex; this manager never touches Hive.
class ContactsSyncManager {
  ContactsSyncManager({
    SupabaseClient? supabase,
    Connectivity? connectivity,
  })  : _supabaseOverride = supabase,
        _connectivity = connectivity ?? Connectivity();

  final SupabaseClient? _supabaseOverride;
  final Connectivity _connectivity;

  static const _connectivityTimeout = Duration(seconds: 3);
  static const _batchSize = 50;

  SupabaseClient? get _supabase {
    if (_supabaseOverride != null) return _supabaseOverride;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// One-shot online probe with a 3s cap. Returns true on timeout/failure
  /// so the caller can still attempt the request and surface the real
  /// network error if it fails.
  Future<bool> isOnline() async {
    try {
      final result = await _connectivity
          .checkConnectivity()
          .timeout(_connectivityTimeout);
      return !result.contains(ConnectivityResult.none);
    } on TimeoutException {
      AppLogger.warning('Connectivity check timed out');
      return true;
    } catch (_) {
      AppLogger.warning('Could not check connectivity');
      return true;
    }
  }

  /// Stream of connectivity changes. The notifier listens so it can
  /// auto-sync when the device reconnects.
  Stream<List<ConnectivityResult>> onConnectivityChanged() =>
      _connectivity.onConnectivityChanged;

  /// Push any unsynced contacts in bulk (one round-trip per batch of 50).
  /// Falls back to per-contact upserts if the batch fails (network blip,
  /// server rejects one row, etc).
  Future<void> pushUnsyncedBatch({
    required String userId,
    required List<ContactModel> unsynced,
  }) async {
    final supabase = _supabase;
    if (supabase == null || unsynced.isEmpty) return;

    for (var i = 0; i < unsynced.length; i += _batchSize) {
      final batch = unsynced.skip(i).take(_batchSize).toList();
      final payload = batch.map((c) => c.toSupabase(userId)).toList();

      try {
        await supabase
            .from('emergency_contacts')
            .upsert(payload, onConflict: 'id');
        AppLogger.info('Batch pushed ${batch.length} contacts');
      } catch (_) {
        AppLogger.warning(
            'Batch push failed, falling back to individual inserts');
        for (final contact in batch) {
          try {
            await supabase
                .from('emergency_contacts')
                .upsert(contact.toSupabase(userId), onConflict: 'id');
          } catch (_) {
            AppLogger.warning('Could not push contact ${contact.id}');
          }
        }
      }
    }
  }

  /// Push a single contact. `isNew=true` routes to INSERT; otherwise UPDATE
  /// is scoped to `(id, user_id)` so Supabase RLS keeps the update local
  /// to the caller.
  Future<PushOutcome> pushOne({
    required String userId,
    required ContactModel contact,
    required bool isNew,
  }) async {
    final supabase = _supabase;
    if (supabase == null) {
      AppLogger.warning('Cannot sync to Supabase: not logged in');
      return PushOutcome.failure;
    }

    try {
      final data = contact.toSupabase(userId);
      if (isNew) {
        await supabase.from('emergency_contacts').insert(data);
      } else {
        await supabase
            .from('emergency_contacts')
            .update(data)
            .eq('id', contact.id)
            .eq('user_id', userId);
      }
      AppLogger.info('Contact synced to Supabase: ${contact.id}');
      return PushOutcome.success;
    } catch (e) {
      AppLogger.error('Error syncing contact to Supabase', e);
      return PushOutcome.failure;
    }
  }

  /// Fetch this user's contacts from Supabase. Never mutates local state.
  /// Callers merge + persist under their own lock.
  Future<PullResult> fetchRemote({required String userId}) async {
    final supabase = _supabase;
    if (supabase == null) {
      return PullResult(remoteContacts: const [], fetchedCount: 0);
    }
    try {
      final response = await supabase
          .from('emergency_contacts')
          .select()
          .eq('user_id', userId);
      final remote = response
          .whereType<Map<String, dynamic>>()
          .map(ContactModel.fromSupabase)
          .toList();
      return PullResult(remoteContacts: remote, fetchedCount: remote.length);
    } catch (e) {
      AppLogger.error('Error syncing from Supabase', e);
      rethrow;
    }
  }

  /// Delete a single contact. Returns true on success so callers know
  /// whether to drop it from the `pendingDeletes` queue or retry later.
  Future<bool> deleteOne({
    required String userId,
    required String contactId,
  }) async {
    final supabase = _supabase;
    if (supabase == null) {
      AppLogger.warning('Cannot delete from Supabase: not logged in');
      return false;
    }
    try {
      await supabase
          .from('emergency_contacts')
          .delete()
          .eq('id', contactId)
          .eq('user_id', userId);
      AppLogger.info('Contact deleted from Supabase: $contactId');
      return true;
    } catch (e) {
      AppLogger.error('Error deleting from Supabase', e);
      return false;
    }
  }

  /// Retry any queued deletes that failed while offline. Returns the set
  /// of IDs that were successfully removed so the caller can prune them
  /// from its state.
  Future<Set<String>> retryPendingDeletes({
    required String userId,
    required List<String> pendingIds,
  }) async {
    if (_supabase == null || pendingIds.isEmpty) return const <String>{};
    final successful = <String>{};
    for (final id in pendingIds) {
      if (await deleteOne(userId: userId, contactId: id)) {
        successful.add(id);
      }
    }
    if (successful.isNotEmpty) {
      AppLogger.info('Retried ${successful.length} pending deletes');
    }
    return successful;
  }

  /// Filter unknown exceptions into the three categories the notifier
  /// already branches on, saving the per-case `on X catch` at the call
  /// site.
  static SyncExceptionKind classify(Object e) {
    if (e is TimeoutException) return SyncExceptionKind.timeout;
    if (e is SocketException) return SyncExceptionKind.network;
    if (e is PostgrestException) return SyncExceptionKind.server;
    return SyncExceptionKind.unknown;
  }
}

enum SyncExceptionKind { timeout, network, server, unknown }
