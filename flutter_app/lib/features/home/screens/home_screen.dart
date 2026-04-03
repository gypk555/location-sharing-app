import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/models/contact_model.dart';
import '../../../core/models/location_model.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/contacts_provider.dart';
import '../../../core/providers/location_provider.dart';
import '../../../core/providers/password_breach_provider.dart';
import '../../../core/providers/sos_provider.dart';
import '../../../core/services/sms_service.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/utils/logger.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Check for breach warning after frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _showBreachWarningIfNeeded();
        // Ensure contacts are loaded
        ref.read(contactsProvider.notifier).ensureSyncedForCurrentUser();
      }
    });
  }

  /// Show breach warning banner if flag is set
  void _showBreachWarningIfNeeded() {
    final shouldShow = ref.read(showBreachWarningProvider);
    if (!shouldShow) return;

    // Reset the flag immediately
    ref.read(showBreachWarningProvider.notifier).state = false;

    // Show the banner
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showMaterialBanner(
      MaterialBanner(
        backgroundColor: Colors.orange.shade50,
        leading: const Icon(Icons.warning_amber, color: Colors.orange),
        content: const Text(
          'Your password was found in a data breach. '
          'We recommend changing it for your safety.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              scaffoldMessenger.hideCurrentMaterialBanner();
              // TODO: Navigate to change password screen when implemented
            },
            child: const Text('Change Password'),
          ),
          TextButton(
            onPressed: () {
              // Set "don't show again" flag and persist to storage
              ref.read(dontShowBreachWarningProvider.notifier).setDontShowAgain(true);
              scaffoldMessenger.hideCurrentMaterialBanner();
            },
            child: const Text("Don't Show Again"),
          ),
          TextButton(
            onPressed: () {
              scaffoldMessenger.hideCurrentMaterialBanner();
            },
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }

  /// Share current location with contacts that have location sharing enabled
  Future<void> _shareLocation() async {
    final locationState = ref.read(locationProvider);

    // Ensure contacts are loaded before proceeding
    await ref.read(contactsProvider.notifier).ensureSyncedForCurrentUser();

    // Re-read contacts state after ensuring they're loaded
    final contactsState = ref.read(contactsProvider);

    // Debug: Log contact states
    AppLogger.debug('Total contacts: ${contactsState.contacts.length}');
    for (final contact in contactsState.contacts) {
      AppLogger.debug('Contact ${contact.name} - isLocationSharing: ${contact.isLocationSharing}');
    }
    AppLogger.debug('Location sharing contacts: ${contactsState.locationSharingContacts.length}');

    // Check if location tracking is enabled
    if (!locationState.isTracking) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enable location tracking first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Check if current location is available
    if (locationState.currentLocation == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Getting current location...'),
        ),
      );
      return;
    }

    // Get contacts with location sharing enabled
    final sharingContacts = contactsState.locationSharingContacts;
    if (sharingContacts.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No contacts enabled for location sharing'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Show custom app selection dialog with icons
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Open with'),
        content: SizedBox(
          width: double.maxFinite,
          child: GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: [
              _AppIcon(
                label: 'WhatsApp',
                icon: FontAwesomeIcons.whatsapp,
                color: const Color(0xFF25D366),
                onTap: () {
                  Navigator.pop(dialogContext);
                  _shareViaWhatsApp(sharingContacts, locationState.currentLocation!);
                },
              ),
              _AppIcon(
                label: 'Messages',
                icon: FontAwesomeIcons.comment,
                color: const Color(0xFF0084FF),
                onTap: () {
                  Navigator.pop(dialogContext);
                  _shareViaSms(sharingContacts, locationState.currentLocation!);
                },
              ),
              _AppIcon(
                label: 'Telegram',
                icon: FontAwesomeIcons.telegram,
                color: const Color(0xFF0088cc),
                onTap: () {
                  Navigator.pop(dialogContext);
                  _shareViaTelegram(sharingContacts, locationState.currentLocation!);
                },
              ),
              _AppIcon(
                label: 'More',
                icon: FontAwesomeIcons.share,
                color: Colors.grey,
                onTap: () {
                  Navigator.pop(dialogContext);
                  _shareViaMoreApps(sharingContacts, locationState.currentLocation!);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  /// Share location via SMS (pre-fills all phone numbers)
  Future<void> _shareViaSms(
    List<ContactModel> contacts,
    LocationModel location,
  ) async {
    try {
      final smsService = SmsService();
      final success = await smsService.shareLocationViaSms(
        contacts: contacts,
        location: location,
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location shared successfully'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to share via SMS'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      AppLogger.error('Error sharing via SMS', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error sharing location'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Share location via WhatsApp (one contact at a time for multiple)
  Future<void> _shareViaWhatsApp(
    List<ContactModel> contacts,
    LocationModel location,
  ) async {
    try {
      final smsService = SmsService();
      final sentCount = await smsService.shareLocationViaWhatsApp(
        contacts: contacts,
        location: location,
      );

      if (mounted) {
        if (sentCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Location shared successfully with $sentCount contact(s)'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sharing cancelled'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      AppLogger.error('Error sharing via WhatsApp', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error sharing location'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Share location via Telegram (one contact at a time for multiple)
  Future<void> _shareViaTelegram(
    List<ContactModel> contacts,
    LocationModel location,
  ) async {
    try {
      final smsService = SmsService();
      final sentCount = await smsService.shareLocationViaTelegram(
        contacts: contacts,
        location: location,
      );

      if (mounted) {
        if (sentCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Location shared successfully with $sentCount contact(s)'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sharing cancelled'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      AppLogger.error('Error sharing via Telegram', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error sharing location'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Share location via other apps using native chooser
  Future<void> _shareViaMoreApps(
    List<ContactModel> contacts,
    LocationModel location,
  ) async {
    try {
      final smsService = SmsService();
      final wasShared = await smsService.shareLocationWithMoreApps(
        contacts: contacts,
        location: location,
      );

      if (mounted) {
        if (wasShared) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location shared successfully'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sharing cancelled'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      AppLogger.error('Error sharing via more apps', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error sharing location'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  onTap: _shareLocation,
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

class _AppIcon extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _AppIcon({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: color,
              size: 32,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
