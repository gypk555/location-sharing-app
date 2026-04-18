import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../app/routes.dart';
import '../../../../core/providers/live_sharing_provider.dart';
import '../../../../core/providers/location_provider.dart';
import '../../../../core/services/background_service.dart';
import '../../../../core/services/live_location_sharing_service.dart';
import '../../../../shared/theme/app_theme.dart';
import '../widgets/live_map_view.dart';

/// Active-session view shown to the sharer while a live share is running.
/// Renders:
///   - The map of the sharer's own current location
///   - The list of recipients with live indicators
///   - A big "Stop sharing" button
///   - Per-recipient share actions (WhatsApp / Telegram / SMS / more)
class ActiveShareScreen extends ConsumerStatefulWidget {
  const ActiveShareScreen({super.key});

  @override
  ConsumerState<ActiveShareScreen> createState() => _ActiveShareScreenState();
}

/// Lightweight point used locally in this screen. Combines positions
/// coming from two sources: the background-isolate stream (primary,
/// streaming) and a one-shot UI-isolate fix (fallback, fast).
class _Point {
  final double latitude;
  final double longitude;
  final double? accuracy;
  final double? heading;
  final DateTime timestamp;
  _Point({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.heading,
    required this.timestamp,
  });
}

class _ActiveShareScreenState extends ConsumerState<ActiveShareScreen> {
  Timer? _ticker;
  StreamSubscription<Map<String, dynamic>?>? _bgPositionSub;
  _Point? _latest;

  @override
  void initState() {
    super.initState();

    // Periodic redraw so LiveMapView can re-evaluate its staleness badge
    // (kStaleThreshold = 60s). 5s is a pragmatic middle ground — the
    // previous 1s interval forced ~3,600 full-subtree rebuilds/hour just
    // to refresh a badge that changes at most once per minute.
    _ticker = Timer.periodic(
      const Duration(seconds: 5),
      (_) => mounted ? setState(() {}) : null,
    );

    // Subscribe to positions emitted by the background isolate. This is
    // the primary stream while a share is active — the background isolate
    // owns the only geolocator subscription (to avoid duplicate drain).
    _bgPositionSub = BackgroundService.positionStream().listen((data) {
      if (!mounted || data == null) return;
      final lat = (data['latitude'] as num?)?.toDouble();
      final lng = (data['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) return;
      setState(() {
        _latest = _Point(
          latitude: lat,
          longitude: lng,
          accuracy: (data['accuracy'] as num?)?.toDouble(),
          heading: (data['heading'] as num?)?.toDouble(),
          timestamp: data['timestamp'] != null
              ? DateTime.parse(data['timestamp'] as String)
              : DateTime.now(),
        );
      });
    });

    // Fetch an immediate one-shot fix so the map has something to show
    // while we wait for the background stream's first emission (which
    // can take a few seconds as the service spins up).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(locationProvider.notifier).getCurrentLocation();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _bgPositionSub?.cancel();
    super.dispose();
  }

  /// Prefer the background-stream point (always fresh). Fall back to the
  /// locationProvider's currentLocation (one-shot fix from initState) if
  /// the background stream hasn't emitted yet.
  _Point? _effectiveLoc(LocationState locationState) {
    if (_latest != null) return _latest;
    final fallback = locationState.currentLocation;
    if (fallback == null) return null;
    return _Point(
      latitude: fallback.latitude,
      longitude: fallback.longitude,
      accuracy: fallback.accuracy,
      heading: fallback.heading,
      timestamp: fallback.timestamp,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Navigate away when the session is inactive. The old
    // addPostFrameCallback inside an if-branch scheduled a route push on
    // every frame while inactive. Using ref.listen (deduped across
    // rebuilds) fires once per state change. We do NOT gate on
    // `prev.isActive` because a cold start where the provider's very
    // first emission is already inactive would otherwise leave the user
    // stranded on the loading spinner forever.
    ref.listen<LiveSharingState>(liveSharingProvider, (prev, next) {
      if (!next.isActive && mounted) {
        context.go(AppRoutes.home);
      }
    });
    final sharing = ref.watch(liveSharingProvider);
    final locationState = ref.watch(locationProvider);

    if (!sharing.isActive) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final loc = _effectiveLoc(locationState);

    return Scaffold(
      appBar: AppBar(
        title: Text(sharing.isSosTriggered ? 'SOS: Sharing live' : 'Sharing live'),
        backgroundColor:
            sharing.isSosTriggered ? AppTheme.errorColor : AppTheme.primaryColor,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: loc == null
                ? const _WaitingForFirstFix()
                : LiveMapView(
                    latitude: loc.latitude,
                    longitude: loc.longitude,
                    accuracyMeters: loc.accuracy,
                    headingDegrees: loc.heading,
                    lastUpdated: loc.timestamp,
                    label: 'You',
                  ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              color: AppTheme.backgroundColor,
              child: Column(
                children: [
                  _StatusHeader(
                    recipientCount: sharing.recipients.length,
                    isSos: sharing.isSosTriggered,
                  ),
                  if (sharing.isHydrated)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      color: AppTheme.warningColor.withValues(alpha: 0.12),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 16, color: AppTheme.warningColor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'This session was started in a previous run',
                              style: TextStyle(
                                color: AppTheme.warningColor,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: sharing.recipients.length,
                      itemBuilder: (_, i) => _RecipientCard(
                        recipient: sharing.recipients[i],
                        onRemove: () => _removeRecipient(sharing.recipients[i]),
                        onShareLink: () => _shareLink(sharing.recipients[i]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              foregroundColor: AppTheme.errorColor,
              side: BorderSide(color: AppTheme.errorColor),
            ),
            onPressed: _confirmStop,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text(
              'Stop sharing',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _removeRecipient(SharedRecipient r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Stop sharing with ${r.name}?'),
        content: Text(
          'This will end the live share for ${r.name} only. Other recipients '
          'will continue to see your location.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref
          .read(liveSharingProvider.notifier)
          .stopRecipient(r.sharingRowId);
    }
  }

  Future<void> _shareLink(SharedRecipient r) async {
    // Copy the existing share_plus flow used by home_screen.dart — user
    // picks WhatsApp/Telegram/SMS/etc from the native app chooser.
    await Share.share(
      'Track my live location: ${r.publicUrl}',
      subject: 'My live location',
    );
  }

  Future<void> _confirmStop() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Stop live sharing?'),
        content: const Text(
          'Your emergency contacts will no longer see your location. '
          'You can start a new share at any time.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep sharing')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.errorColor),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(liveSharingProvider.notifier).stop();
    }
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.recipientCount, required this.isSos});
  final int recipientCount;
  final bool isSos;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: isSos
          ? AppTheme.errorColor.withValues(alpha: 0.08)
          : AppTheme.successColor.withValues(alpha: 0.08),
      child: Row(
        children: [
          Icon(
            isSos ? Icons.emergency : Icons.gps_fixed,
            color: isSos ? AppTheme.errorColor : AppTheme.successColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isSos
                  ? 'SOS active: sharing with $recipientCount ${recipientCount == 1 ? "contact" : "contacts"}'
                  : 'Sharing with $recipientCount ${recipientCount == 1 ? "contact" : "contacts"}',
              style: TextStyle(
                color: isSos ? AppTheme.errorColor : AppTheme.successColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecipientCard extends StatelessWidget {
  const _RecipientCard({
    required this.recipient,
    required this.onRemove,
    required this.onShareLink,
  });

  final SharedRecipient recipient;
  final VoidCallback onRemove;
  final VoidCallback onShareLink;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: recipient.isRegistered
                  ? AppTheme.successColor.withValues(alpha: 0.15)
                  : AppTheme.textSecondary.withValues(alpha: 0.15),
              child: Icon(
                recipient.isRegistered ? Icons.phone_android : Icons.link,
                size: 18,
                color: recipient.isRegistered
                    ? AppTheme.successColor
                    : AppTheme.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recipient.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    recipient.isRegistered
                        ? 'Seeing your location live'
                        : 'Tap "Share link" to send',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (!recipient.isRegistered)
              IconButton(
                tooltip: 'Share link',
                icon: const Icon(Icons.ios_share),
                onPressed: onShareLink,
              ),
            IconButton(
              tooltip: 'Stop for this recipient',
              icon: Icon(Icons.close, color: AppTheme.errorColor),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

class _WaitingForFirstFix extends StatelessWidget {
  const _WaitingForFirstFix();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.backgroundColor,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Getting your first location…',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}
