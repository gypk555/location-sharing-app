import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../features/live_sharing/providers/incoming_shares_provider.dart';
import '../../../shared/theme/app_theme.dart';

/// Dismissable banner shown on the home screen when one or more registered
/// contacts are actively sharing their live location with the current user.
/// Tapping it opens the receiver view for the most recent share. Hidden
/// entirely when there are no active shares, so users never see it in the
/// default state.
class IncomingSharesBanner extends ConsumerWidget {
  const IncomingSharesBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(incomingSharesProvider);
    return async.when(
      data: (shares) {
        if (shares.isEmpty) return const SizedBox.shrink();
        final newest = shares.first;
        final sosCount = shares.where((s) => s.isSosTriggered).length;
        final color = sosCount > 0 ? AppTheme.errorColor : AppTheme.primaryColor;
        final icon = sosCount > 0 ? Icons.emergency : Icons.location_on;
        final title = sosCount > 0
            ? '${newest.ownerName} triggered an SOS'
            : shares.length == 1
                ? '${newest.ownerName} is sharing live location'
                : '${shares.length} people are sharing live location';
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Material(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () =>
                  context.push(AppRoutes.liveShareView(newest.sharingId)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: color,
                      child: Icon(icon, color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Tap to view live map',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: color),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}
