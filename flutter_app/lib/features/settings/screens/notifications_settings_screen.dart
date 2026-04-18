import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../../../core/providers/app_preferences_provider.dart';
import '../../../shared/theme/app_theme.dart';

/// Sub-screen for in-app notification preferences.
///
/// The three toggles persist booleans that future notification call sites
/// (SOS-sent confirmation, live-share-started banner, sync-error alerts)
/// should honor before firing a local notification. Today only the
/// foreground-service notification in background_service.dart actually
/// fires, so flipping these flags doesn't visibly change behavior yet —
/// but the prefs are stored so the UX works correctly once those call
/// sites are wired.
class NotificationsSettingsScreen extends ConsumerWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(appPreferencesProvider);
    final notifier = ref.read(appPreferencesProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'IN-APP ALERTS',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('SOS sent confirmation'),
                  subtitle: const Text(
                    'Show a notification when an SOS alert is delivered',
                  ),
                  secondary: const Icon(Icons.warning_amber),
                  value: prefs.notifySosSent,
                  onChanged: (v) => notifier.setNotificationPref(
                    NotificationKind.sosSent,
                    v,
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Live sharing started'),
                  subtitle: const Text(
                    'Notify when you begin sharing your live location',
                  ),
                  secondary: const Icon(Icons.share_location),
                  value: prefs.notifyLiveShareStarted,
                  onChanged: (v) => notifier.setNotificationPref(
                    NotificationKind.liveShareStarted,
                    v,
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Sync errors'),
                  subtitle: const Text(
                    'Alert when contacts or location fail to sync to cloud',
                  ),
                  secondary: const Icon(Icons.sync_problem),
                  value: prefs.notifySyncErrors,
                  onChanged: (v) => notifier.setNotificationPref(
                    NotificationKind.syncError,
                    v,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'SYSTEM',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Open system notification settings'),
              subtitle: const Text(
                'Change sound, vibration, or block notifications',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => ph.openAppSettings(),
            ),
          ),
        ],
      ),
    );
  }
}
