import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';

import '../../../core/providers/app_preferences_provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/contacts_provider.dart';
import '../../../core/providers/password_breach_provider.dart';
import '../../../core/providers/profile_settings_provider.dart';
import '../../../core/providers/sos_provider.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../core/providers/location_permission_provider.dart';

import '../screens/fake_caller_screen.dart';
import '../widgets/location_permission_dialog.dart';
import '../widgets/theme_mode_dialog.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final sosState = ref.watch(sosProvider);
    // Granular selects so editing any single preference rebuilds only the
    // tile that shows it, not the entire ListView.
    final themeMode = ref.watch(
      appPreferencesProvider.select((s) => s.themeMode),
    );
    final profileSettings = ref.watch(profileSettingsProvider);
    final sosTemplateOverride = profileSettings.sosSettings.sosMessage;
    final fakeCallerName = profileSettings.fakeCallSettings.callerName;
    final fakeCallerNumber = profileSettings.fakeCallSettings.callerNumber;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profile section
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: AppTheme.primaryColor,
                child: Text(
                  (profileSettings.name?.isNotEmpty == true
                          ? profileSettings.name!.substring(0, 1)
                          : authState.user?.name?.substring(0, 1) ?? 'U')
                      .toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(profileSettings.name ?? authState.user?.name ?? 'User'),
              subtitle: Text(
                (profileSettings.phone?.isNotEmpty == true ? profileSettings.phone : null) ??
                authState.user?.phone ??
                authState.user?.email ??
                '',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                final user = authState.user;
                if (user == null) return;
                // Pass a merged user object so the edit screen gets the latest from profileSettings
                final mergedUser = user.copyWith(
                  name: profileSettings.name ?? user.name,
                  phone: profileSettings.phone ?? user.phone,
                );
                context.push(AppRoutes.settingsProfile, extra: mergedUser);
              },
            ),
          ),

          const SizedBox(height: 24),

          // SOS Settings
          const _SectionHeader(title: 'SOS Settings'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Shake to Alert'),
                  subtitle: const Text('Shake phone 3 times to trigger SOS'),
                  secondary: const Icon(Icons.vibration),
                  value: sosState.shakeEnabled,
                  onChanged: (value) {
                    ref.read(sosProvider.notifier).setShakeEnabled(value);
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.timer),
                  title: const Text('SOS Countdown'),
                  subtitle: Text('${sosState.countdownSeconds} seconds'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    _showCountdownPicker(context, ref, sosState.countdownSeconds);
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.message),
                  title: const Text('SOS Message'),
                  subtitle: Text(
                    sosTemplateOverride == null
                        ? 'Default message'
                        : 'Customized',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(AppRoutes.settingsSos),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Fake Call Settings
          const _SectionHeader(title: 'Fake Call'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person),
                  title: const Text('Caller Name'),
                  subtitle: Text(fakeCallerName),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(
                    AppRoutes.settingsFakeCall,
                    extra: FakeCallerField.name,
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.phone),
                  title: const Text('Caller Number'),
                  subtitle: Text(fakeCallerNumber),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(
                    AppRoutes.settingsFakeCall,
                    extra: FakeCallerField.number,
                  ),
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.music_note),
                  title: Text('Ringtone'),
                  // Ringtone picker is blocked on the audio-assets TODO in
                  // CLAUDE.md. Keeping the row visible but non-interactive
                  // so users aren't surprised when it doesn't respond.
                  subtitle: Text('Default (coming soon)'),
                  enabled: false,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // App Settings
          const _SectionHeader(title: 'App'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.notifications),
                  title: const Text('Notifications'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(AppRoutes.notificationsSettings),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.location_on),
                  title: const Text('Location Permissions'),
                  subtitle: Consumer(
                    builder: (context, ref, _) {
                      final async = ref.watch(locationPermissionProvider);
                      return Text(
                        async.maybeWhen(
                          data: (s) => s.label,
                          orElse: () => '…',
                        ),
                      );
                    },
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => const LocationPermissionDialog(),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.dark_mode),
                  title: const Text('Dark Mode'),
                  subtitle: Text(themeModeLabel(themeMode)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => const ThemeModeDialog(),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Data & Backup
          const _SectionHeader(title: 'Data & Backup'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.cloud_upload),
                  title: const Text('Export Contacts'),
                  subtitle: const Text('Share backup file'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _exportContacts(context, ref),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.cloud_download),
                  title: const Text('Import Contacts'),
                  subtitle: const Text('Restore from backup'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _importContacts(context, ref),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // TODO: restore About / Help / Privacy Policy section once the
          // URLs or in-app content exist. Hidden for now to avoid dead rows.

          // Logout
          Card(
            color: AppTheme.errorColor.withValues(alpha: 0.1),
            child: ListTile(
              leading: const Icon(Icons.logout, color: AppTheme.errorColor),
              title: const Text(
                'Logout',
                style: TextStyle(color: AppTheme.errorColor),
              ),
              onTap: () {
                _showLogoutDialog(context, ref);
              },
            ),
          ),

          const SizedBox(height: 16),

          // Version
          const Center(
            child: Text(
              'Version 1.0.0',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _exportContacts(BuildContext context, WidgetRef ref) async {
    final contacts = ref.read(contactsProvider).contacts;

    if (contacts.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No contacts to export. Add some contacts first.'),
            backgroundColor: AppTheme.warningColor,
          ),
        );
      }
      return;
    }

    // Show loading
    unawaited(showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Preparing export...'),
              ],
            ),
          ),
        ),
      ),
    ));

    final result = await ref.read(contactsProvider.notifier).exportContacts();

    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop(); // Close loading dialog

      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported ${result.contactCount} contacts'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      } else {
        // Show detailed error dialog for failures
        _showErrorDialog(
          context,
          title: 'Export Failed',
          error: result.error ?? 'Unknown error',
          recoverySuggestion: result.recoverySuggestion,
          errorCode: result.errorCode,
        );
      }
    }
  }

  Future<void> _importContacts(BuildContext context, WidgetRef ref) async {
    // Show confirmation dialog first (security: prevent accidental imports)
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cloud_download),
            SizedBox(width: 8),
            Text('Import Contacts'),
          ],
        ),
        content: const Text(
          'This will import contacts from a backup file. '
          'Imported contacts will be added to your existing contacts.\n\n'
          'Only import files from trusted sources.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Select File'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    // Show loading
    unawaited(showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Importing contacts...'),
              ],
            ),
          ),
        ),
      ),
    ));

    final result =
        await ref.read(contactsProvider.notifier).importContactsFromFile();

    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop(); // Close loading dialog

      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Imported ${result.contacts.length} contacts'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      } else if (result.error != 'No file selected') {
        // Show detailed error dialog for failures
        _showErrorDialog(
          context,
          title: 'Import Failed',
          error: result.error ?? 'Unknown error',
          recoverySuggestion: result.recoverySuggestion,
          errorCode: result.errorCode,
        );
      }
    }
  }

  void _showErrorDialog(
    BuildContext context, {
    required String title,
    required String error,
    String? recoverySuggestion,
    String? errorCode,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: AppTheme.errorColor),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(error),
            if (recoverySuggestion != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.lightbulb_outline,
                      size: 18,
                      color: AppTheme.primaryColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        recoverySuggestion,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (errorCode != null) ...[
              const SizedBox(height: 12),
              Text(
                'Error code: $errorCode',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showCountdownPicker(BuildContext context, WidgetRef ref, int current) {
    showDialog(
      context: context,
      builder: (context) => _CountdownPickerDialog(
        currentValue: current,
        onSelected: (value) {
          ref.read(sosProvider.notifier).setCountdownSeconds(value);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, WidgetRef ref) {
    final contactsState = ref.read(contactsProvider);
    final unsyncedContacts = contactsState.unsyncedContacts;

    if (unsyncedContacts.isEmpty) {
      // No unsynced contacts, show simple logout dialog
      _showSimpleLogoutDialog(context, ref);
    } else {
      // Has unsynced contacts, show warning dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _UnsyncedContactsLogoutDialog(
          unsyncedCount: unsyncedContacts.length,
        ),
      );
    }
  }

  void _showSimpleLogoutDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await ref.read(contactsProvider.notifier).clearAll();
              // Clear user-specific breach warning preference
              ref.read(dontShowBreachWarningProvider.notifier).clearOnLogout();
              await ref.read(authStateProvider.notifier).signOut();
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF6B7280), // AppTheme.textSecondary
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}

/// Dialog for selecting SOS countdown duration.
/// Uses ListTile with checkmark icons to avoid deprecated Radio APIs.
class _CountdownPickerDialog extends StatefulWidget {
  final int currentValue;
  final ValueChanged<int> onSelected;

  const _CountdownPickerDialog({
    required this.currentValue,
    required this.onSelected,
  });

  @override
  State<_CountdownPickerDialog> createState() => _CountdownPickerDialogState();
}

class _CountdownPickerDialogState extends State<_CountdownPickerDialog> {
  late int _selectedValue;

  @override
  void initState() {
    super.initState();
    _selectedValue = widget.currentValue;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('SOS Countdown'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [3, 5, 10, 15].map((seconds) {
          final isSelected = seconds == _selectedValue;
          return ListTile(
            title: Text('$seconds seconds'),
            leading: Icon(
              isSelected ? Icons.check_circle : Icons.circle_outlined,
              color: isSelected ? AppTheme.primaryColor : null,
            ),
            onTap: () {
              setState(() => _selectedValue = seconds);
            },
          );
        }).toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => widget.onSelected(_selectedValue),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

/// Dialog for handling logout when unsynced contacts exist
class _UnsyncedContactsLogoutDialog extends ConsumerStatefulWidget {
  final int unsyncedCount;

  const _UnsyncedContactsLogoutDialog({required this.unsyncedCount});

  @override
  ConsumerState<_UnsyncedContactsLogoutDialog> createState() =>
      _UnsyncedContactsLogoutDialogState();
}

class _UnsyncedContactsLogoutDialogState
    extends ConsumerState<_UnsyncedContactsLogoutDialog> {
  int _retryCount = 0;
  bool _isSyncing = false;
  bool _syncFailed = false;
  String? _statusMessage;
  String? _recoverySuggestion;

  static const int _maxRetries = 3;

  Future<void> _retrySync() async {
    setState(() {
      _isSyncing = true;
      _statusMessage = 'Syncing... (Attempt ${_retryCount + 1}/$_maxRetries)';
    });

    // Check if online first
    final isOnline = await ref.read(contactsProvider.notifier).isOnline();
    if (!mounted) return;

    if (!isOnline) {
      setState(() {
        _isSyncing = false;
        _statusMessage = 'No internet connection. Please check your network.';
      });
      return;
    }

    final result = await ref.read(contactsProvider.notifier).syncToSupabase();
    if (!mounted) return;

    if (result.success) {
      setState(() {
        _isSyncing = false;
        _statusMessage = 'All contacts synced!';
        _recoverySuggestion = null;
      });

      // Wait a moment then proceed with logout
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        await _performLogout();
      }
    } else {
      _retryCount++;
      if (_retryCount >= _maxRetries) {
        setState(() {
          _isSyncing = false;
          _syncFailed = true;
          _statusMessage = result.wasOffline
              ? 'No internet connection after $_maxRetries attempts.'
              : 'Sync failed after $_maxRetries attempts. ${result.error ?? "Unknown error"}';
          _recoverySuggestion = result.recoverySuggestion ??
              'Export your contacts before logging out to avoid data loss.';
        });
      } else {
        setState(() {
          _isSyncing = false;
          _statusMessage =
              '${result.error ?? "Sync failed"}. ${_maxRetries - _retryCount} retries left.';
          _recoverySuggestion = result.recoverySuggestion;
        });
      }
    }
  }

  Future<void> _exportAndLogout() async {
    setState(() {
      _isSyncing = true;
      _statusMessage = 'Exporting contacts...';
    });

    final result = await ref.read(contactsProvider.notifier).exportContacts();
    if (!mounted) return;

    if (result.success) {
      setState(() {
        _statusMessage = 'Exported ${result.contactCount} contacts!';
      });

      // Show success and logout
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Exported ${result.contactCount} contacts'),
          backgroundColor: AppTheme.successColor,
          duration: const Duration(seconds: 2),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        await _performLogout();
      }
    } else {
      setState(() {
        _isSyncing = false;
        _statusMessage = 'Export failed: ${result.error}';
      });
    }
  }

  Future<void> _performLogout() async {
    await ref.read(contactsProvider.notifier).clearAll();
    // Clear user-specific breach warning preference
    ref.read(dontShowBreachWarningProvider.notifier).clearOnLogout();
    await ref.read(authStateProvider.notifier).signOut();
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.warning_amber, color: AppTheme.warningColor),
          SizedBox(width: 8),
          Text('Unsynced Contacts'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You have ${widget.unsyncedCount} contact(s) not synced to cloud.',
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            'These contacts will be lost if you logout without syncing.',
            style: TextStyle(color: Colors.grey),
          ),
          if (_statusMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _syncFailed
                    ? AppTheme.errorColor.withValues(alpha: 0.1)
                    : AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isSyncing)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      _syncFailed ? Icons.error : Icons.info,
                      size: 16,
                      color: _syncFailed
                          ? AppTheme.errorColor
                          : AppTheme.primaryColor,
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusMessage!,
                      style: TextStyle(
                        fontSize: 13,
                        color: _syncFailed
                            ? AppTheme.errorColor
                            : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // Show recovery suggestion
          if (_recoverySuggestion != null && _syncFailed) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.lightbulb_outline,
                    size: 16,
                    color: AppTheme.primaryColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _recoverySuggestion!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: _isSyncing
          ? []
          : _syncFailed
              ? [
                  // After max retries failed - show export option
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: _exportAndLogout,
                    child: const Text('Export & Logout'),
                  ),
                  TextButton(
                    onPressed: _performLogout,
                    style:
                        TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
                    child: const Text('Logout Anyway'),
                  ),
                ]
              : [
                  // Initial state or retries remaining
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: _retrySync,
                    child: Text(_retryCount == 0 ? 'Retry Sync' : 'Retry Again'),
                  ),
                  TextButton(
                    onPressed: _performLogout,
                    style:
                        TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
                    child: const Text('Logout Anyway'),
                  ),
                ],
    );
  }
}
