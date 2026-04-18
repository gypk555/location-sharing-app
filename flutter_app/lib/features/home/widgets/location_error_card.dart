import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/location_provider.dart';
import '../../../shared/theme/app_theme.dart';

/// Warning banner shown beneath the location-status card when
/// `locationProvider` is carrying an error (service disabled / permission
/// denied / transient failure). Renders nothing when there is no error,
/// so callers can unconditionally drop it into a ListView.
class LocationErrorCard extends ConsumerWidget {
  const LocationErrorCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final error = ref.watch(locationProvider).error;
    if (error == null) return const SizedBox.shrink();

    final notifier = ref.read(locationProvider.notifier);
    final lower = error.toLowerCase();
    final isServiceError = lower.contains('services');
    final isPermissionError = lower.contains('permission');

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        color: AppTheme.warningColor.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                error,
                style: TextStyle(
                  color: AppTheme.warningColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  if (isServiceError)
                    TextButton(
                      onPressed: notifier.openLocationSettings,
                      child: const Text('Open Settings'),
                    ),
                  if (isPermissionError)
                    TextButton(
                      onPressed: notifier.openAppSettings,
                      child: const Text('App Settings'),
                    ),
                  TextButton(
                    onPressed: notifier.clearError,
                    child: const Text('Dismiss'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
