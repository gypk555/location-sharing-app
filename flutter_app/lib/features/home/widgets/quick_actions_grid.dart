import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/providers/contacts_provider.dart';
import '../../../core/providers/live_sharing_provider.dart';
import '../../../shared/theme/app_theme.dart';
import 'quick_action_card.dart';

/// 2-column grid of the four Home quick actions.
/// `onShareLocation` is injected from the screen because the share flow
/// needs access to home-screen state (ScaffoldMessenger, mounted guard).
class QuickActionsGrid extends ConsumerWidget {
  final VoidCallback onShareLocation;

  const QuickActionsGrid({
    super.key,
    required this.onShareLocation,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Derive SOS count from contactsProvider so it stays in sync with
    // add/remove/toggle — SosNotifier only loads it once at init.
    final sosCount = ref.watch(
      contactsProvider.select((s) => s.sosContacts.length),
    );
    final liveSharingState = ref.watch(liveSharingProvider);

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.2,
      children: [
        QuickActionCard(
          icon: Icons.phone_callback,
          title: 'Fake Call',
          subtitle: 'Escape situations',
          color: Colors.blue,
          onTap: () => context.push(AppRoutes.fakeCall),
        ),
        QuickActionCard(
          icon: Icons.location_on,
          title: 'Send Location',
          subtitle: 'One-time message',
          color: Colors.green,
          onTap: onShareLocation,
        ),
        QuickActionCard(
          icon: Icons.people,
          title: 'SOS Contacts',
          subtitle: '$sosCount contacts',
          color: Colors.orange,
          onTap: () => context.go(AppRoutes.contacts),
        ),
        QuickActionCard(
          icon: Icons.share_location,
          title: liveSharingState.isActive ? 'Sharing live' : 'Live Location',
          subtitle: liveSharingState.isActive
              ? 'Tap to view or stop'
              : 'Share in real time',
          color: liveSharingState.isActive
              ? AppTheme.successColor
              : Colors.purple,
          onTap: () => context.push(
            liveSharingState.isActive
                ? AppRoutes.liveShareActive
                : AppRoutes.liveShareStart,
          ),
        ),
      ],
    );
  }
}
