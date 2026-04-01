import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/contacts_provider.dart';
import '../../../core/models/contact_model.dart';
import '../../../shared/theme/app_theme.dart';

class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  @override
  void initState() {
    super.initState();
    // Trigger sync once when screen loads (proper lifecycle, not in build)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Check mounted to prevent operations on disposed widget
      if (mounted) {
        ref.read(contactsProvider.notifier).ensureSyncedForCurrentUser();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final contactsState = ref.watch(contactsProvider);
    final contacts = contactsState.contacts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Contacts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => context.push('/add-contact'),
          ),
        ],
      ),
      body: contacts.isEmpty
          ? _EmptyState(
              onAddPressed: () => context.push('/add-contact'),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: contacts.length,
              itemBuilder: (context, index) {
                final contact = contacts[index];
                return _ContactCard(
                  key: ValueKey(contact.id),
                  contact: contact,
                  onToggleSos: () {
                    ref.read(contactsProvider.notifier).toggleSosContact(contact.id);
                  },
                  onToggleLocation: () {
                    ref.read(contactsProvider.notifier).toggleLocationSharing(contact.id);
                  },
                  onEdit: () {
                    context.push('/add-contact', extra: contact);
                  },
                  onDelete: () {
                    _showDeleteDialog(contact);
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/add-contact'),
        icon: const Icon(Icons.person_add),
        label: const Text('Add Contact'),
      ),
    );
  }

  void _showDeleteDialog(ContactModel contact) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Contact'),
        content: Text('Remove ${contact.name} from emergency contacts?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ref.read(contactsProvider.notifier).removeContact(contact.id);
              Navigator.pop(dialogContext);
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAddPressed;

  const _EmptyState({required this.onAddPressed});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 80,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(height: 24),
            Text(
              'No Emergency Contacts',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Add trusted people who will be notified during emergencies',
              style: TextStyle(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: onAddPressed,
              icon: const Icon(Icons.add),
              label: const Text('Add First Contact'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final ContactModel contact;
  final VoidCallback onToggleSos;
  final VoidCallback onToggleLocation;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ContactCard({
    super.key,
    required this.contact,
    required this.onToggleSos,
    required this.onToggleLocation,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppTheme.primaryColor,
                  child: Text(
                    contact.name.substring(0, 1).toUpperCase(),
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
                      Row(
                        children: [
                          Text(
                            contact.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Sync status indicator
                          if (!contact.isSynced)
                            Tooltip(
                              message: 'Not synced to cloud',
                              child: Icon(
                                Icons.cloud_off,
                                size: 16,
                                color: AppTheme.warningColor,
                              ),
                            )
                          else
                            Tooltip(
                              message: 'Synced to cloud',
                              child: Icon(
                                Icons.cloud_done,
                                size: 16,
                                color: AppTheme.successColor,
                              ),
                            ),
                        ],
                      ),
                      Text(
                        contact.phone,
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                      if (contact.relationship != null)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            contact.relationship!,
                            style: TextStyle(
                              color: AppTheme.primaryColor,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  color: AppTheme.primaryColor,
                  onPressed: onEdit,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  color: AppTheme.errorColor,
                  onPressed: onDelete,
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: _ToggleOption(
                    icon: Icons.warning_amber,
                    label: 'SOS Alerts',
                    isEnabled: contact.isSosContact,
                    onTap: onToggleSos,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ToggleOption(
                    icon: Icons.location_on,
                    label: 'Location',
                    isEnabled: contact.isLocationSharing,
                    onTap: onToggleLocation,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isEnabled;
  final VoidCallback onTap;

  const _ToggleOption({
    required this.icon,
    required this.label,
    required this.isEnabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: isEnabled
              ? AppTheme.successColor.withValues(alpha: 0.1)
              : Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isEnabled ? AppTheme.successColor : AppTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isEnabled ? AppTheme.successColor : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
