import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/location_provider.dart';
import '../../../shared/theme/app_theme.dart';

/// Location-tracking toggle + current-address readout.
/// Watches `locationProvider` and delegates start/stop to its notifier.
class LocationStatusCard extends ConsumerWidget {
  const LocationStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationState = ref.watch(locationProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.location_on,
                  color: locationState.isTracking
                      ? AppTheme.successColor
                      : AppTheme.textSecondary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Location Tracking',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                Switch(
                  value: locationState.isTracking,
                  onChanged: (value) {
                    final notifier = ref.read(locationProvider.notifier);
                    if (value) {
                      notifier.startTracking();
                    } else {
                      notifier.stopTracking();
                    }
                  },
                ),
              ],
            ),
            if (locationState.currentLocation != null) ...[
              const SizedBox(height: 8),
              Text(
                locationState.currentLocation!.address ??
                    'Lat: ${locationState.currentLocation!.latitude.toStringAsFixed(4)}, '
                        'Lng: ${locationState.currentLocation!.longitude.toStringAsFixed(4)}',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
