import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/contacts_provider.dart';
import '../../../core/providers/password_breach_provider.dart';
import '../../../core/providers/sos_provider.dart';
import '../../../shared/theme/app_theme.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final sosState = ref.watch(sosProvider);

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
                  authState.user?.name?.substring(0, 1).toUpperCase() ?? 'U',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(authState.user?.name ?? 'User'),
              subtitle: Text(
                authState.user?.phone ?? authState.user?.email ?? '',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                // Navigate to profile edit
              },
            ),
          ),

          const SizedBox(height: 24),

          // SOS Settings
          _SectionHeader(title: 'SOS Settings'),
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
                  subtitle: const Text('Customize emergency message'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    // Navigate to message customization
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Fake Call Settings
          _SectionHeader(title: 'Fake Call'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person),
                  title: const Text('Caller Name'),
                  subtitle: const Text('Mom'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    // Edit caller name
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.phone),
                  title: const Text('Caller Number'),
                  subtitle: const Text('+1 234 567 8900'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    // Edit caller number
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.music_note),
                  title: const Text('Ringtone'),
                  subtitle: const Text('Default'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    // Select ringtone
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // App Settings
          _SectionHeader(title: 'App'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.notifications),
                  title: const Text('Notifications'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.location_on),
                  title: const Text('Location Permissions'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.dark_mode),
                  title: const Text('Dark Mode'),
                  subtitle: const Text('System default'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Data & Backup
          _SectionHeader(title: 'Data & Backup'),
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

          // About & Support
          _SectionHeader(title: 'About'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info),
                  title: const Text('About Safety App'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.help),
                  title: const Text('Help & Support'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.privacy_tip),
                  title: const Text('Privacy Policy'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Logout
          Card(
            color: AppTheme.errorColor.withValues(alpha: 0.1),
            child: ListTile(
              leading: Icon(Icons.logout, color: AppTheme.errorColor),
              title: Text(
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
          Center(
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
          SnackBar(
            content: const Text('No contacts to export. Add some contacts first.'),
            backgroundColor: AppTheme.warningColor,
          ),
        );
      }
      return;
    }

    // Show loading
    showDialog(
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
    );

    final result = await ref.read(contactsProvider.notifier).exportContacts();

    if (context.mounted) {
      Navigator.pop(context); // Close loading dialog

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
    showDialog(
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
    );

    final result =
        await ref.read(contactsProvider.notifier).importContactsFromFile();

    if (context.mounted) {
      Navigator.pop(context); // Close loading dialog

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
            Icon(Icons.error_outline, color: AppTheme.errorColor),
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
                    Icon(
                      Icons.lightbulb_outline,
                      size: 18,
                      color: AppTheme.primaryColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        recoverySuggestion,
                        style: TextStyle(
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
                style: TextStyle(
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
    if (!isOnline) {
      setState(() {
        _isSyncing = false;
        _statusMessage = 'No internet connection. Please check your network.';
      });
      return;
    }

    final result = await ref.read(contactsProvider.notifier).syncToSupabase();

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

    if (result.success) {
      setState(() {
        _statusMessage = 'Exported ${result.contactCount} contacts!';
      });

      // Show success and logout
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported ${result.contactCount} contacts'),
            backgroundColor: AppTheme.successColor,
            duration: const Duration(seconds: 2),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 500));
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
      title: Row(
        children: [
          Icon(Icons.warning_amber, color: AppTheme.warningColor),
          const SizedBox(width: 8),
          const Text('Unsynced Contacts'),
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
                  Icon(
                    Icons.lightbulb_outline,
                    size: 16,
                    color: AppTheme.primaryColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _recoverySuggestion!,
                      style: TextStyle(
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
