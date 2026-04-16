import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/models/contact_model.dart';
import '../../../../core/providers/contacts_provider.dart';
import '../../../../core/providers/live_sharing_provider.dart';
import '../../../../core/services/live_location_sharing_service.dart';
import '../../../../shared/theme/app_theme.dart';

/// Starting screen for a manual live-share session. Collects:
///   1. Which emergency contacts to share with (multi-select)
///   2. How long the session should run
/// Then calls LiveSharingNotifier.startManual.
class StartShareScreen extends ConsumerStatefulWidget {
  const StartShareScreen({super.key});

  @override
  ConsumerState<StartShareScreen> createState() => _StartShareScreenState();
}

class _StartShareScreenState extends ConsumerState<StartShareScreen> {
  final Set<String> _selectedContactIds = <String>{};
  ShareDuration _duration = ShareDuration.oneHour;

  @override
  Widget build(BuildContext context) {
    final contactsState = ref.watch(contactsProvider);
    final liveState = ref.watch(liveSharingProvider);
    final allContacts = contactsState.contacts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Share Live Location'),
      ),
      body: allContacts.isEmpty
          ? _EmptyContactsState(onAdd: () => context.push('/add-contact'))
          : _buildBody(allContacts, liveState),
      bottomNavigationBar: allContacts.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: _canStart(liveState) ? () => _start(allContacts) : null,
                  icon: liveState.isStarting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Icon(Icons.share_location),
                  label: Text(
                    _selectedContactIds.isEmpty
                        ? 'Select contacts'
                        : 'Start sharing with ${_selectedContactIds.length}'
                            ' ${_selectedContactIds.length == 1 ? "contact" : "contacts"}',
                  ),
                ),
              ),
            ),
    );
  }

  bool _canStart(LiveSharingState s) =>
      _selectedContactIds.isNotEmpty && !s.isStarting;

  Widget _buildBody(List<ContactModel> contacts, LiveSharingState state) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('How long?'),
        const SizedBox(height: 8),
        _DurationPicker(
          value: _duration,
          onChanged: (d) => setState(() => _duration = d),
        ),
        const SizedBox(height: 24),
        _sectionTitle('Who to share with?'),
        const SizedBox(height: 4),
        Text(
          'Registered contacts see a live map in the app. Others get an SMS, '
          'WhatsApp, or Telegram link to a private web page.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 12),
        ...contacts.map((c) => _ContactRow(
              contact: c,
              selected: _selectedContactIds.contains(c.id),
              onToggle: (v) {
                setState(() {
                  if (v) {
                    _selectedContactIds.add(c.id);
                  } else {
                    _selectedContactIds.remove(c.id);
                  }
                });
              },
            )),
        if (state.error != null) ...[
          const SizedBox(height: 12),
          Card(
            color: AppTheme.errorColor.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: AppTheme.errorColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.error!,
                      style: TextStyle(color: AppTheme.errorColor),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      );

  Future<void> _start(List<ContactModel> allContacts) async {
    final selected = allContacts
        .where((c) => _selectedContactIds.contains(c.id))
        .toList();
    if (selected.isEmpty) return;

    final ok = await ref
        .read(liveSharingProvider.notifier)
        .startManual(contacts: selected, duration: _duration);

    if (!mounted) return;
    if (ok) {
      context.pushReplacement('/live-share/active');
    }
  }
}

class _DurationPicker extends StatelessWidget {
  const _DurationPicker({required this.value, required this.onChanged});
  final ShareDuration value;
  final ValueChanged<ShareDuration> onChanged;

  static const _labels = {
    ShareDuration.fifteenMinutes: '15 min',
    ShareDuration.oneHour: '1 hour',
    ShareDuration.eightHours: '8 hours',
    ShareDuration.untilStopped: 'Until I stop',
  };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: ShareDuration.values.map((d) {
        final isSelected = d == value;
        return ChoiceChip(
          label: Text(_labels[d]!),
          selected: isSelected,
          showCheckmark: false,
          onSelected: (_) => onChanged(d),
          backgroundColor: Colors.white,
          selectedColor: AppTheme.primaryColor,
          side: BorderSide(
            color: isSelected
                ? AppTheme.primaryColor
                : AppTheme.textSecondary.withValues(alpha: 0.4),
            width: 1.2,
          ),
          labelStyle: TextStyle(
            color: isSelected ? Colors.white : AppTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        );
      }).toList(),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.contact,
    required this.selected,
    required this.onToggle,
  });

  final ContactModel contact;
  final bool selected;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final isRegistered = contact.isRegisteredUser;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: CheckboxListTile(
        value: selected,
        onChanged: (v) => onToggle(v ?? false),
        controlAffinity: ListTileControlAffinity.trailing,
        title: Text(
          contact.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Row(
          children: [
            Text(contact.phone),
            const SizedBox(width: 8),
            if (contact.resolvedAt != null)
              _DeliveryBadge(isRegistered: isRegistered),
          ],
        ),
      ),
    );
  }
}

class _DeliveryBadge extends StatelessWidget {
  const _DeliveryBadge({required this.isRegistered});
  final bool isRegistered;

  @override
  Widget build(BuildContext context) {
    final color = isRegistered ? AppTheme.successColor : AppTheme.textSecondary;
    final label = isRegistered ? 'In-app' : 'Link';
    final icon = isRegistered ? Icons.phone_android : Icons.link;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyContactsState extends StatelessWidget {
  const _EmptyContactsState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline,
              size: 96, color: AppTheme.textSecondary.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text(
            'No emergency contacts yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Add a contact first to start sharing your live location.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            ),
            onPressed: onAdd,
            icon: const Icon(Icons.person_add),
            label: const Text('Add contact'),
          ),
        ],
      ),
    );
  }
}
