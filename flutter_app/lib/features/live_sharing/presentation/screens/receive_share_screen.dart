import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../shared/theme/app_theme.dart';
import '../widgets/live_map_view.dart';

/// Full-screen receiver view: renders a live map + details panel for
/// one active share where the current user is the recipient. The share
/// is identified by the `location_sharing.id` passed in the route.
///
/// Location updates come from a Supabase Realtime subscription on
/// `location_history` filtered by the owner. RLS (policy
/// "Shared users can view shared locations") guarantees the caller
/// can only see rows for owners who actively share with them.
class ReceiveShareScreen extends ConsumerStatefulWidget {
  const ReceiveShareScreen({super.key, required this.sharingId});

  final String sharingId;

  @override
  ConsumerState<ReceiveShareScreen> createState() =>
      _ReceiveShareScreenState();
}

class _ReceiveShareScreenState extends ConsumerState<ReceiveShareScreen> {
  RealtimeChannel? _channel;
  Timer? _uiTicker;

  Map<String, dynamic>? _latestLocation;
  bool _ended = false;
  String? _ownerName;
  bool _isSos = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    // Refresh the "last updated X ago" display and staleness badge.
    // 5s is a pragmatic balance — previously 1s caused ~3,600 full
    // rebuilds per hour for a label that only needs coarse refresh.
    _uiTicker = Timer.periodic(
      const Duration(seconds: 5),
      (_) => mounted ? setState(() {}) : null,
    );
  }

  @override
  void dispose() {
    _uiTicker?.cancel();
    if (_channel != null) {
      Supabase.instance.client.removeChannel(_channel!);
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final client = Supabase.instance.client;
    try {
      // Explicit column list: avoid pulling back columns we don't render
      // (shared_with_phone etc.) — PII hygiene if RLS is ever misconfigured.
      final row = await client
          .from('location_sharing')
          .select('id,owner_id,is_active,revoked_at,trigger_source')
          .eq('id', widget.sharingId)
          .maybeSingle();
      if (!mounted) return;
      if (row == null) {
        setState(() => _ended = true);
        return;
      }
      final ownerId = row['owner_id'] as String;
      // Fetch the sharer's display name from their profile. Isolated in
      // its own try/catch so a profile fetch failure (RLS denial, missing
      // row, transient error) falls back to a generic label rather than
      // collapsing the whole share into "Share ended".
      try {
        final ownerProfile = await client
            .from('profiles')
            .select('name')
            .eq('id', ownerId)
            .maybeSingle();
        if (!mounted) return;
        _ownerName = (ownerProfile?['name'] as String?) ?? 'Contact';
      } catch (_) {
        if (!mounted) return;
        _ownerName = 'Contact';
      }
      _isSos = (row['trigger_source'] as String?) == 'sos';
      if (row['is_active'] != true || row['revoked_at'] != null) {
        setState(() => _ended = true);
        return;
      }

      // Fetch the most recent known position so we don't start on a
      // blank map while waiting for the next realtime event. Explicitly
      // omit `address` — the geocoded street address is a potential
      // doxxing vector (home / shelter) and the UI renders coordinates
      // only.
      final latest = await client
          .from('location_history')
          .select('latitude,longitude,accuracy,heading,speed,created_at')
          .eq('user_id', ownerId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (!mounted) return;
      if (latest != null) {
        setState(() => _latestLocation = latest);
      } else {
        setState(() {}); // trigger a rebuild to show owner info
      }

      // Subscribe to realtime inserts on location_history for this owner.
      _channel = client
          .channel('recv_share_${widget.sharingId}')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'location_history',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: ownerId,
            ),
            callback: (payload) {
              final newRow = payload.newRecord;
              if (!mounted) return;
              setState(() => _latestLocation = newRow);
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'location_sharing',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: widget.sharingId,
            ),
            callback: (payload) {
              final newRow = payload.newRecord;
              if (newRow['is_active'] == false || newRow['revoked_at'] != null) {
                if (!mounted) return;
                setState(() => _ended = true);
              }
            },
          )
          .subscribe();
    } catch (e) {
      if (!mounted) return;
      setState(() => _ended = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = _latestLocation;
    return Scaffold(
      appBar: AppBar(
        title: Text(_ownerName ?? 'Live location'),
        backgroundColor:
            _isSos ? AppTheme.errorColor : AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: loc == null
                ? _ended
                    ? const _EndedPlaceholder()
                    : const Center(child: CircularProgressIndicator())
                : LiveMapView(
                    latitude: (loc['latitude'] as num).toDouble(),
                    longitude: (loc['longitude'] as num).toDouble(),
                    accuracyMeters: (loc['accuracy'] as num?)?.toDouble(),
                    headingDegrees: (loc['heading'] as num?)?.toDouble(),
                    lastUpdated: loc['created_at'] != null
                        ? DateTime.parse(loc['created_at'] as String)
                        : null,
                    label: _ownerName,
                    ended: _ended,
                  ),
          ),
          _DetailsPanel(
            latest: loc,
            ended: _ended,
            isSos: _isSos,
            onOpenInMaps: loc == null ? null : () => _openInExternalMap(loc),
          ),
        ],
      ),
    );
  }

  Future<void> _openInExternalMap(Map<String, dynamic> loc) async {
    final lat = (loc['latitude'] as num).toDouble();
    final lng = (loc['longitude'] as num).toDouble();
    final url = Uri.parse('https://maps.google.com/?q=$lat,$lng');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }
}

class _DetailsPanel extends StatelessWidget {
  const _DetailsPanel({
    required this.latest,
    required this.ended,
    required this.isSos,
    required this.onOpenInMaps,
  });

  final Map<String, dynamic>? latest;
  final bool ended;
  final bool isSos;
  final VoidCallback? onOpenInMaps;

  @override
  Widget build(BuildContext context) {
    final loc = latest;
    DateTime? ts;
    if (loc != null && loc['created_at'] != null) {
      ts = DateTime.parse(loc['created_at'] as String);
    }
    final elapsed = ts == null ? null : DateTime.now().difference(ts);

    return Container(
      padding: const EdgeInsets.all(16),
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isSos && !ended)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.errorColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.emergency, color: AppTheme.errorColor, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Emergency SOS is active',
                    style: TextStyle(
                      color: AppTheme.errorColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          if (loc != null) ...[
            // Coordinates only — the reverse-geocoded address is not
            // displayed to receivers (see _bootstrap comment for why).
            _row(
              Icons.location_on,
              '${(loc['latitude'] as num).toStringAsFixed(5)}, ${(loc['longitude'] as num).toStringAsFixed(5)}',
            ),
            const SizedBox(height: 6),
            _row(
              Icons.access_time,
              elapsed == null
                  ? 'Just now'
                  : 'Updated ${_humanizeAgo(elapsed)} (${_fmtTime(ts!)})',
            ),
            if (loc['speed'] != null) ...[
              const SizedBox(height: 6),
              _row(
                Icons.speed,
                '${((loc['speed'] as num).toDouble() * 3.6).toStringAsFixed(1)} km/h',
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: onOpenInMaps,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Open in Google Maps'),
                  ),
                ),
              ],
            ),
          ] else if (ended) ...[
            _row(Icons.info_outline, 'This live share has ended.'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => Navigator.of(context).canPop()
                  ? Navigator.pop(context)
                  : GoRouter.of(context).go('/'),
              child: const Text('Close'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppTheme.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
          ),
        ),
      ],
    );
  }

  String _fmtTime(DateTime t) =>
      DateFormat('h:mm:ss a').format(t.toLocal());

  String _humanizeAgo(Duration d) {
    if (d.inSeconds < 5) return 'just now';
    if (d.inSeconds < 60) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    return '${d.inHours}h ago';
  }
}

class _EndedPlaceholder extends StatelessWidget {
  const _EndedPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.backgroundColor,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.location_off, size: 64, color: AppTheme.textSecondary),
          const SizedBox(height: 12),
          Text(
            'Share ended',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}
