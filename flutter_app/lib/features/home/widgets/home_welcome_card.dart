import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../shared/theme/app_theme.dart';

/// Greeting card shown at the top of the Home screen.
/// Watches `authStateProvider` for the user's display name and initial.
class HomeWelcomeCard extends ConsumerWidget {
  const HomeWelcomeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).user;
    final initial = user?.name?.substring(0, 1).toUpperCase() ?? 'U';
    final name = user?.name ?? 'User';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: AppTheme.primaryColor,
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hello, $name',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  Text(
                    'Stay safe today',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.shield,
              color: AppTheme.successColor,
              size: 32,
            ),
          ],
        ),
      ),
    );
  }
}
