import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/location_permission_provider.dart';
import '../../../shared/theme/app_theme.dart';

class LocationPermissionDialog extends ConsumerWidget {
  const LocationPermissionDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(locationPermissionProvider);

    return AlertDialog(
      title: const Text('Location Permissions'),
      content: async.when(
        loading: () => const SizedBox(
          height: 48,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Text('Could not read status: $e'),
        data: (snap) {
          final statusColor = snap.isGranted
              ? AppTheme.successColor
              : snap.isDeniedForever
                  ? AppTheme.errorColor
                  : AppTheme.warningColor;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.location_on, color: statusColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      snap.label,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                snap.isGranted
                    ? 'Location is available for SOS, live sharing, and '
                        'emergency features.'
                    : 'Location access is required for SOS alerts and live '
                        'sharing to work correctly.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        async.maybeWhen(
          data: (snap) {
            if (snap.isGranted) return const SizedBox.shrink();
            if (!snap.serviceEnabled) {
              return TextButton(
                onPressed: () async {
                  await LocationPermissionActions.openLocationSettings();
                  ref.invalidate(locationPermissionProvider);
                },
                child: const Text('Turn on location'),
              );
            }
            if (snap.isDeniedForever) {
              return TextButton(
                onPressed: () async {
                  await LocationPermissionActions.openAppSettings();
                  ref.invalidate(locationPermissionProvider);
                },
                child: const Text('Open app settings'),
              );
            }
            return TextButton(
              onPressed: () async {
                await LocationPermissionActions.request();
                ref.invalidate(locationPermissionProvider);
              },
              child: const Text('Request permission'),
            );
          },
          orElse: () => const SizedBox.shrink(),
        ),
      ],
    );
  }
}
