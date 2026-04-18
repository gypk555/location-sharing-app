import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/contact_model.dart';
import '../../../core/models/location_model.dart';
import '../../../core/providers/contacts_provider.dart';
import '../../../core/providers/location_provider.dart';
import '../../../core/providers/password_breach_provider.dart';
import '../../../core/services/sms_service.dart';
import '../../../shared/utils/logger.dart';
import '../widgets/app_chooser_dialog.dart';
import '../widgets/home_welcome_card.dart';
import '../widgets/incoming_shares_banner.dart';
import '../widgets/location_error_card.dart';
import '../widgets/location_status_card.dart';
import '../widgets/quick_actions_grid.dart';
import '../widgets/safety_tip_card.dart';

/// Home screen.
///
/// Orchestrates the home layout and owns only side-effectful concerns
/// (breach-warning banner, location-error SnackBar, share-location flow).
/// All visual sections live in `../widgets/*.dart` — see code-review
/// finding §3.3 for the rationale behind the split.
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
    _locationErrorSub = ref.listenManual<LocationState>(locationProvider,
        (previous, next) {
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
              ref
                  .read(dontShowBreachWarningProvider.notifier)
                  .setDontShowAgain(true);
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
      unawaited(
        ref.read(contactsProvider.notifier).ensureSyncedForCurrentUser(),
      );
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
        const SnackBar(content: Text('Getting current location...')),
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
      builder: (dialogContext) => AppChooserDialog(
        onWhatsApp: () {
          Navigator.pop(dialogContext);
          if (mounted) _shareViaWhatsApp(sharingContacts, location);
        },
        onSms: () {
          Navigator.pop(dialogContext);
          if (mounted) _shareViaSms(sharingContacts, location);
        },
        onTelegram: () {
          Navigator.pop(dialogContext);
          if (mounted) _shareViaTelegram(sharingContacts, location);
        },
        onMore: () {
          Navigator.pop(dialogContext);
          if (mounted) _shareViaMoreApps(location);
        },
      ),
    );
  }

  Future<void> _shareViaSms(
    List<ContactModel> contacts,
    LocationModel location,
  ) async {
    try {
      final success = await _smsService.shareLocationViaSms(
        contacts: contacts,
        location: location,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? 'Location shared successfully' : 'Failed to share via SMS',
          ),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      AppLogger.error('Error sharing via SMS', e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error sharing location'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _shareViaWhatsApp(
    List<ContactModel> contacts,
    LocationModel location,
  ) async {
    try {
      final sentCount = await _smsService.shareLocationViaWhatsApp(
        contacts: contacts,
        location: location,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sentCount > 0
                ? 'WhatsApp opened - select contacts to share location'
                : 'Sharing cancelled',
          ),
          backgroundColor: sentCount > 0 ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      AppLogger.error('Error sharing via WhatsApp', e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error sharing location'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _shareViaTelegram(
    List<ContactModel> contacts,
    LocationModel location,
  ) async {
    try {
      final sentCount = await _smsService.shareLocationViaTelegram(
        contacts: contacts,
        location: location,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sentCount > 0
                ? 'Telegram opened - select contacts to share location'
                : 'Sharing cancelled',
          ),
          backgroundColor: sentCount > 0 ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      AppLogger.error('Error sharing via Telegram', e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error sharing location'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _shareViaMoreApps(LocationModel location) async {
    try {
      final wasShared = await _smsService.shareLocationWithMoreApps(
        location: location,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasShared ? 'Location shared successfully' : 'Sharing cancelled',
          ),
          backgroundColor: wasShared ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      AppLogger.error('Error sharing via more apps', e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error sharing location'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
            const HomeWelcomeCard(),
            const SizedBox(height: 16),
            const LocationStatusCard(),
            const LocationErrorCard(),
            const SizedBox(height: 24),
            const IncomingSharesBanner(),
            Text(
              'Quick Actions',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            QuickActionsGrid(onShareLocation: _shareLocation),
            const SizedBox(height: 24),
            const SafetyTipCard(),
          ],
        ),
      ),
    );
  }
}
