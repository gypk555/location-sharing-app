import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/auth_provider.dart';

/// A single live share that the current user is receiving from another user.
/// Derived from a row in `location_sharing` where `shared_with_id = me`.
class IncomingShare {
  final String sharingId;
  final String ownerId;
  final String ownerName;
  final String shareToken;
  final DateTime? expiresAt;
  final bool isSosTriggered;
  final DateTime? lastHeartbeatAt;

  IncomingShare({
    required this.sharingId,
    required this.ownerId,
    required this.ownerName,
    required this.shareToken,
    required this.expiresAt,
    required this.isSosTriggered,
    required this.lastHeartbeatAt,
  });

  factory IncomingShare.fromRow(Map<String, dynamic> row) {
    return IncomingShare(
      sharingId: row['id'] as String,
      ownerId: row['owner_id'] as String,
      ownerName: (row['shared_with_name'] as String?) ?? 'Someone',
      shareToken: row['share_token'] as String,
      expiresAt: row['expires_at'] != null
          ? DateTime.parse(row['expires_at'] as String)
          : null,
      isSosTriggered: (row['trigger_source'] as String?) == 'sos',
      lastHeartbeatAt: row['last_heartbeat_at'] != null
          ? DateTime.parse(row['last_heartbeat_at'] as String)
          : null,
    );
  }
}

/// Stream of active shares where the current user is the recipient.
///
/// Strategy: query a filtered list, then use a Supabase Realtime
/// subscription on the `location_sharing` table to trigger re-queries
/// whenever any row changes. RLS ensures only shares the current user is
/// authorized to see come back. The realtime subscription acts as a
/// change-notification bus; the actual data always comes from the
/// filtered SELECT so we can trust RLS.
final incomingSharesProvider =
    StreamProvider.autoDispose<List<IncomingShare>>((ref) {
  final auth = ref.watch(authStateProvider);
  final userId = auth.user?.id;
  if (userId == null) {
    return Stream.value(const <IncomingShare>[]);
  }

  final client = Supabase.instance.client;
  final controller = StreamController<List<IncomingShare>>();

  Future<void> pushLatest() async {
    try {
      final rows = await client
          .from('location_sharing')
          .select()
          .eq('shared_with_id', userId)
          .eq('is_active', true)
          .order('created_at', ascending: false);
      if (!controller.isClosed) {
        controller.add(
          (rows as List)
              .cast<Map<String, dynamic>>()
              .map(IncomingShare.fromRow)
              .toList(),
        );
      }
    } catch (e, stack) {
      // Propagate errors so the UI can distinguish "network down" from
      // "no active shares" — the StreamProvider's .when(error:) will
      // render an appropriate state. StateError from a closed controller
      // is harmless here (provider was disposed).
      if (!controller.isClosed) {
        try {
          controller.addError(e, stack);
        } on StateError {
          // Controller closed between the check and the add — ignore.
        }
      }
    }
  }

  // Kick off the initial snapshot.
  pushLatest();

  // Realtime subscription: re-query on any change to location_sharing
  // that targets the current user. Without this filter every sharer's
  // heartbeat UPDATE (from every user in the system) would wake every
  // recipient client and trigger a redundant SELECT — unnecessary
  // load at scale and a minor metadata leak if Realtime RLS is ever
  // misconfigured in the Supabase dashboard.
  //
  // NOTE: `shared_with_id` is NULL for contacts who aren't registered
  // Supabase users (they receive an SMS link to the public web
  // receiver instead). Those rows intentionally never match this
  // filter — the in-app incoming-shares UI only applies to registered
  // recipients. Do NOT add a shared_with_phone OR-branch without
  // re-evaluating the receiver flow end-to-end.
  final channel = client
      .channel('incoming_shares_$userId')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'location_sharing',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'shared_with_id',
          value: userId,
        ),
        callback: (_) => pushLatest(),
      )
      .subscribe();

  ref.onDispose(() {
    client.removeChannel(channel);
    controller.close();
  });

  return controller.stream;
});
