import 'dart:async';
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
import '../../../core/providers/live_sharing_provider.dart';
import '../../../features/live_sharing/providers/incoming_shares_provider.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/utils/logger.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  // Singleton SMS service instance - cached at class level for reuse
  final _smsService = SmsService();
  ProviderSubscription<LocationState>? _locationErrorSub;
  // Cached reference to the root ScaffoldMessenger so we can dismiss the
  // breach warning MaterialBanner in dispose() without touching `context`.
  // MaterialBanners live on the root ScaffoldMessenger above the router and
  // would otherwise persist across logout back to the login screen.
  ScaffoldMessengerState? _scaffoldMessenger;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _locationErrorSub = ref.listenManual<LocationState>(locationProvider, (previous, next) {
      final prevError = previous?.error;
      final nextError = next.error;
      if (nextError == null || nextError == prevError) return;
      // Use the cached _scaffoldMessenger instead of ScaffoldMessenger.of(context)
      // so this callback stays safe even if it fires mid-teardown. The cache is
      // populated in didChangeDependencies before the listener can ever fire,
      // since Riverpod delivers the first callback asynchronously.
      final messenger = _scaffoldMessenger;
      if (messenger == null) return;
      final isServiceError = nextError.contains('Location services');
      final isPermissionError = nextError.contains('permission');
      messenger.showSnackBar(
        SnackBar(
          content: Text(nextError),
          backgroundColor: Colors.orange,
          action: isServiceError
              ? SnackBarAction(
                  label: 'Open Settings',
                  textColor: Colors.white,
                  onPressed: () {
                    ref.read(locationProvider.notifier).openLocationSettings();
                  },
                )
              : isPermissionError
                  ? SnackBarAction(
                      label: 'App Settings',
                      textColor: Colors.white,
                      onPressed: () {
                        ref.read(locationProvider.notifier).openAppSettings();
                      },
                    )
                  : null,
        ),
      );
    });
    // Check for breach warning after frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _showBreachWarningIfNeeded();
        // Ensure contacts are loaded
        ref.read(contactsProvider.notifier).ensureSyncedForCurrentUser();
        // Clear any stale "location services/permission" error if the user
        // has since fixed it in system settings. Only clears when conditions
        // are actually resolved (see LocationNotifier.refreshErrorState).
        ref.read(locationProvider.notifier).refreshErrorState();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // When the app resumes from background, the user may have just returned
    // from system settings after enabling location / granting permission.
    // Re-check so the stale error banner disappears.
    if (state == AppLifecycleState.resumed && mounted) {
      ref.read(locationProvider.notifier).refreshErrorState();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scaffoldMessenger = ScaffoldMessenger.of(context);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scaffoldMessenger?.hideCurrentMaterialBanner();
    _locationErrorSub?.close();
    super.dispose();
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
    final contactsState = ref.read(contactsProvider);

    // Check if already syncing - don't block UI waiting for sync
    if (contactsState.isSyncing) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Loading contacts... please wait'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Use existing contacts if available (offline-first pattern)
    // Trigger background sync if contacts list is empty (non-blocking)
    if (contactsState.contacts.isEmpty) {
      unawaited(ref.read(contactsProvider.notifier).ensureSyncedForCurrentUser());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Loading contacts in background...'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Validate location tracking and current location
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

    // Show app chooser dialog
    if (!mounted) return;
    final location = locationState.currentLocation!;
    showDialog(
      context: context,
      builder: (dialogContext) => _AppChooserDialog(
        onWhatsApp: () {
          Navigator.pop(dialogContext);
          // Check mounted before calling async operation
          if (mounted) {
            _shareViaWhatsApp(sharingContacts, location);
          }
        },
        onSms: () {
          Navigator.pop(dialogContext);
          // Check mounted before calling async operation
          if (mounted) {
            _shareViaSms(sharingContacts, location);
          }
        },
        onTelegram: () {
          Navigator.pop(dialogContext);
          // Check mounted before calling async operation
          if (mounted) {
            _shareViaTelegram(sharingContacts, location);
          }
        },
        onMore: () {
          Navigator.pop(dialogContext);
          // Check mounted before calling async operation
          if (mounted) {
            _shareViaMoreApps(location);
          }
        },
      ),
    );
  }

  /// Share location via SMS (pre-fills all phone numbers)
  Future<void> _shareViaSms(
    List<ContactModel> contacts,
    LocationModel location,
  ) async {
    try {
      final success = await _smsService.shareLocationViaSms(
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
      final sentCount = await _smsService.shareLocationViaWhatsApp(
        contacts: contacts,
        location: location,
      );

      if (mounted) {
        if (sentCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('WhatsApp opened - select contacts to share location'),
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
      final sentCount = await _smsService.shareLocationViaTelegram(
        contacts: contacts,
        location: location,
      );

      if (mounted) {
        if (sentCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Telegram opened - select contacts to share location'),
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
    LocationModel location,
  ) async {
    try {
      final wasShared = await _smsService.shareLocationWithMoreApps(
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
    final liveSharingState = ref.watch(liveSharingProvider);

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

            if (locationState.error != null) ...[
              const SizedBox(height: 12),
              Card(
                color: AppTheme.warningColor.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        locationState.error!,
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
                          if (locationState.error!
                              .toLowerCase()
                              .contains('services'))
                            TextButton(
                              onPressed: () {
                                ref
                                    .read(locationProvider.notifier)
                                    .openLocationSettings();
                              },
                              child: const Text('Open Settings'),
                            ),
                          if (locationState.error!
                              .toLowerCase()
                              .contains('permission'))
                            TextButton(
                              onPressed: () {
                                ref
                                    .read(locationProvider.notifier)
                                    .openAppSettings();
                              },
                              child: const Text('App Settings'),
                            ),
                          TextButton(
                            onPressed: () {
                              ref.read(locationProvider.notifier).clearError();
                            },
                            child: const Text('Dismiss'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Incoming live shares banner (shown only when someone is
            // sharing their live location with the current user).
            const _IncomingSharesBanner(),

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
                  icon: Icons.share_location,
                  title: liveSharingState.isActive
                      ? 'Sharing live'
                      : 'Live Location',
                  subtitle: liveSharingState.isActive
                      ? 'Tap to view or stop'
                      : 'Share in real time',
                  color: liveSharingState.isActive
                      ? AppTheme.successColor
                      : Colors.purple,
                  onTap: () => context.push(
                    liveSharingState.isActive
                        ? '/live-share/active'
                        : '/live-share/start',
                  ),
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

/// Dialog for selecting which app to use for sharing location
class _AppChooserDialog extends StatelessWidget {
  final VoidCallback onWhatsApp;
  final VoidCallback onSms;
  final VoidCallback onTelegram;
  final VoidCallback onMore;

  const _AppChooserDialog({
    required this.onWhatsApp,
    required this.onSms,
    required this.onTelegram,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Open with'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 200),
        child: SizedBox(
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
                onTap: onWhatsApp,
              ),
              _AppIcon(
                label: 'Messages',
                icon: FontAwesomeIcons.comment,
                color: const Color(0xFF0084FF),
                onTap: onSms,
              ),
              _AppIcon(
                label: 'Telegram',
                icon: FontAwesomeIcons.telegram,
                color: const Color(0xFF0088cc),
                onTap: onTelegram,
              ),
              _AppIcon(
                label: 'More',
                icon: FontAwesomeIcons.share,
                color: Colors.grey,
                onTap: onMore,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
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
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

/// Dismissable banner shown on the home screen when one or more registered
/// contacts are actively sharing their live location with the current user.
/// Tapping it opens the receiver view for the most recent share. Hidden
/// entirely when there are no active shares, so users never see it in the
/// default state.
class _IncomingSharesBanner extends ConsumerWidget {
  const _IncomingSharesBanner();

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
              onTap: () => context.push('/live-share/view/${newest.sharingId}'),
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
                          Text(
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
