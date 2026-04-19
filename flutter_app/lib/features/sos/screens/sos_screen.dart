import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/sos_provider.dart';
import '../../../core/services/sos_service.dart';
import '../../../shared/theme/app_theme.dart';

class SosScreen extends ConsumerWidget {
  const SosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sosState = ref.watch(sosProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SOS'),
        backgroundColor: AppTheme.sosButtonColor,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // SOS Button
                    _SosButton(
                      status: sosState.status,
                      countdown: sosState.countdown,
                      onTap: () {
                        if (sosState.status == SosStatus.idle) {
                          ref.read(sosProvider.notifier).triggerSosWithCountdown();
                        } else if (sosState.status == SosStatus.countdown) {
                          ref.read(sosProvider.notifier).cancelSos();
                        }
                      },
                      onLongPress: () {
                        ref.read(sosProvider.notifier).triggerSosImmediately();
                      },
                    ),

                    const SizedBox(height: 32),

                    // Status text
                    Text(
                      _getStatusText(sosState.status, sosState.countdown),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _getStatusSubtext(sosState.status),
                      style: const TextStyle(color: AppTheme.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

            // Bottom info
            Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.people, color: AppTheme.textSecondary),
                      const SizedBox(width: 8),
                      Text(
                        '${sosState.sosContactCount} SOS contacts configured',
                        style: const TextStyle(color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _InfoCard(
                          icon: Icons.vibration,
                          title: 'Shake Alert',
                          subtitle: sosState.shakeEnabled ? 'Enabled' : 'Disabled',
                          isActive: sosState.shakeEnabled,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _InfoCard(
                          icon: Icons.timer,
                          title: 'Countdown',
                          subtitle: '${sosState.countdownSeconds}s',
                          isActive: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getStatusText(SosStatus status, int countdown) {
    switch (status) {
      case SosStatus.idle:
        return 'Press for SOS';
      case SosStatus.countdown:
        return 'Sending in $countdown...';
      case SosStatus.triggered:
        return 'SOS Triggered!';
      case SosStatus.sending:
        return 'Sending Alerts...';
      case SosStatus.sent:
        return 'Alerts Sent!';
      case SosStatus.partiallySent:
        return 'Alerts Partially Sent';
      case SosStatus.failed:
        return 'Failed to Send';
    }
  }

  String _getStatusSubtext(SosStatus status) {
    switch (status) {
      case SosStatus.idle:
        return 'Long press for immediate SOS';
      case SosStatus.countdown:
        return 'Tap again to cancel';
      case SosStatus.triggered:
        return 'Getting your location...';
      case SosStatus.sending:
        return 'Contacting your emergency contacts';
      case SosStatus.sent:
        return 'Your contacts have been alerted';
      case SosStatus.partiallySent:
        return 'Some contacts could not be reached';
      case SosStatus.failed:
        return 'Please check your contacts and try again';
    }
  }
}

class _SosButton extends StatelessWidget {
  final SosStatus status;
  final int countdown;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _SosButton({
    required this.status,
    required this.countdown,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = status == SosStatus.countdown ||
        status == SosStatus.triggered ||
        status == SosStatus.sending;

    // Accessibility: screen-reader users rely on a button announcement
    // with clear tap/long-press semantics. Without this, TalkBack/VoiceOver
    // announce only "button" which is useless in an emergency
    // (code-review finding §7.1).
    final semanticsLabel = switch (status) {
      SosStatus.idle => 'SOS emergency button',
      SosStatus.countdown => 'SOS countdown, $countdown seconds remaining',
      SosStatus.triggered => 'SOS triggered, getting your location',
      SosStatus.sending => 'Sending SOS alerts',
      SosStatus.sent => 'SOS alerts sent',
      SosStatus.partiallySent => 'SOS alerts partially sent',
      SosStatus.failed => 'SOS failed to send',
    };
    final tapHint = status == SosStatus.idle
        ? 'start a 5-second countdown'
        : status == SosStatus.countdown
            ? 'cancel the countdown'
            : null;

    return Semantics(
      button: true,
      enabled: true,
      label: semanticsLabel,
      hint: status == SosStatus.idle
          ? 'Double tap to start a 5-second countdown. '
              'Long press to send an SOS immediately to your emergency contacts.'
          : null,
      onTapHint: tapHint,
      onLongPressHint: status == SosStatus.idle
          ? 'send SOS immediately'
          : null,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? AppTheme.sosButtonPressedColor : AppTheme.sosButtonColor,
            boxShadow: [
              BoxShadow(
                color: AppTheme.sosButtonColor.withValues(alpha: 0.4),
                blurRadius: isActive ? 30 : 20,
                spreadRadius: isActive ? 10 : 5,
              ),
            ],
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (status == SosStatus.countdown)
                  Text(
                    '$countdown',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 64,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                else if (status == SosStatus.sending || status == SosStatus.triggered)
                  const SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 4,
                    ),
                  )
                else if (status == SosStatus.sent)
                  const Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 64,
                  )
                else if (status == SosStatus.failed)
                  const Icon(
                    Icons.error_outline,
                    color: Colors.white,
                    size: 64,
                  )
                else
                  const Text(
                    'SOS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isActive;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              icon,
              color: isActive ? AppTheme.successColor : AppTheme.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
