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
    } catch (_) {
      if (!controller.isClosed) controller.add(const <IncomingShare>[]);
    }
  }

  // Kick off the initial snapshot.
  pushLatest();

  // Realtime subscription: re-query on any change to location_sharing.
  final channel = client
      .channel('incoming_shares_$userId')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'location_sharing',
        callback: (_) => pushLatest(),
      )
      .subscribe();

  ref.onDispose(() {
    client.removeChannel(channel);
    controller.close();
  });

  return controller.stream;
});
