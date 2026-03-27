import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/location_provider.dart';
import '../../../core/providers/sos_provider.dart';
import '../../../shared/theme/app_theme.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final locationState = ref.watch(locationProvider);
    final sosState = ref.watch(sosProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Safety App'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Welcome card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: AppTheme.primaryColor,
                          child: Text(
                            authState.user?.name?.substring(0, 1).toUpperCase() ?? 'U',
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
                                'Hello, ${authState.user?.name ?? 'User'}',
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
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Location status card
            Card(
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
                            if (value) {
                              ref.read(locationProvider.notifier).startTracking();
                            } else {
                              ref.read(locationProvider.notifier).stopTracking();
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
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Quick actions grid
            Text(
              'Quick Actions',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),

            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.2,
              children: [
                _QuickActionCard(
                  icon: Icons.phone_callback,
                  title: 'Fake Call',
                  subtitle: 'Escape situations',
                  color: Colors.blue,
                  onTap: () => context.push('/fake-call'),
                ),
                _QuickActionCard(
                  icon: Icons.location_on,
                  title: 'Share Location',
                  subtitle: 'Send to contacts',
                  color: Colors.green,
                  onTap: () {
                    // Share location
                  },
                ),
                _QuickActionCard(
                  icon: Icons.people,
                  title: 'SOS Contacts',
                  subtitle: '${sosState.sosContactCount} contacts',
                  color: Colors.orange,
                  onTap: () => context.go('/contacts'),
                ),
                _QuickActionCard(
                  icon: Icons.mic,
                  title: 'Record Audio',
                  subtitle: 'Evidence mode',
                  color: Colors.purple,
                  onTap: () {
                    // Start recording
                  },
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Safety tips
            Card(
              color: AppTheme.primaryColor.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lightbulb, color: AppTheme.primaryColor),
                        const SizedBox(width: 8),
                        Text(
                          'Safety Tip',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Shake your phone 3 times quickly to trigger an SOS alert. '
                      'Make sure you have added emergency contacts.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
