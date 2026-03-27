import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
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
            onPressed: () {
              ref.read(authStateProvider.notifier).signOut();
              Navigator.pop(context);
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
        style: TextStyle(
          color: AppTheme.textSecondary,
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
