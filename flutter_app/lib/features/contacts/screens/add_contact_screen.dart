import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers/contacts_provider.dart';
import '../../../core/models/contact_model.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/utils/validators.dart';

class AddContactScreen extends ConsumerStatefulWidget {
  const AddContactScreen({super.key});

  @override
  ConsumerState<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends ConsumerState<AddContactScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  String _relationship = 'family';
  bool _isSosContact = true;
  bool _isLocationSharing = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _saveContact() async {
    if (!_formKey.currentState!.validate()) return;

    // Normalize the phone number
    final normalizedPhone = Validators.normalizePhone(_phoneController.text);

    final contact = ContactModel(
      id: const Uuid().v4(),
      name: Validators.sanitizeName(_nameController.text),
      phone: normalizedPhone,
      email: _emailController.text.trim().isEmpty
          ? null
          : _emailController.text.trim().toLowerCase(),
      relationship: _relationship,
      isSosContact: _isSosContact,
      isLocationSharing: _isLocationSharing,
      addedAt: DateTime.now(),
    );

    await ref.read(contactsProvider.notifier).addContact(contact);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${contact.name} added successfully')),
      );
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Contact'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        actions: [
          TextButton(
            onPressed: _saveContact,
            child: const Text(
              'Save',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Avatar
              Center(
                child: CircleAvatar(
                  radius: 48,
                  backgroundColor: AppTheme.primaryColor,
                  child: Icon(
                    Icons.person,
                    size: 48,
                    color: Colors.white,
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Name
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name *',
                  prefixIcon: Icon(Icons.person),
                ),
                validator: Validators.validateName,
              ),

              const SizedBox(height: 16),

              // Phone
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone Number *',
                  prefixIcon: Icon(Icons.phone),
                  hintText: '+91 98765 43210',
                  helperText: 'Valid phone number is critical for SOS alerts',
                ),
                validator: Validators.validatePhone,
              ),

              const SizedBox(height: 16),

              // Email (optional)
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email (optional)',
                  prefixIcon: Icon(Icons.email),
                ),
                validator: (value) => Validators.validateEmail(value, allowEmpty: true),
              ),

              const SizedBox(height: 24),

              // Relationship
              Text(
                'Relationship',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _RelationshipChip(
                    label: 'Family',
                    value: 'family',
                    selectedValue: _relationship,
                    onSelected: (v) => setState(() => _relationship = v),
                  ),
                  _RelationshipChip(
                    label: 'Friend',
                    value: 'friend',
                    selectedValue: _relationship,
                    onSelected: (v) => setState(() => _relationship = v),
                  ),
                  _RelationshipChip(
                    label: 'Emergency',
                    value: 'emergency',
                    selectedValue: _relationship,
                    onSelected: (v) => setState(() => _relationship = v),
                  ),
                  _RelationshipChip(
                    label: 'Other',
                    value: 'other',
                    selectedValue: _relationship,
                    onSelected: (v) => setState(() => _relationship = v),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Permissions
              Text(
                'Permissions',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),

              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('SOS Contact'),
                      subtitle: const Text(
                        'Receive emergency alerts and SOS messages',
                      ),
                      secondary: Icon(
                        Icons.warning_amber,
                        color: _isSosContact
                            ? AppTheme.sosButtonColor
                            : AppTheme.textSecondary,
                      ),
                      value: _isSosContact,
                      onChanged: (value) => setState(() => _isSosContact = value),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('Location Sharing'),
                      subtitle: const Text(
                        'Can view your real-time location',
                      ),
                      secondary: Icon(
                        Icons.location_on,
                        color: _isLocationSharing
                            ? AppTheme.successColor
                            : AppTheme.textSecondary,
                      ),
                      value: _isLocationSharing,
                      onChanged: (value) =>
                          setState(() => _isLocationSharing = value),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              ElevatedButton(
                onPressed: _saveContact,
                child: const Text('Save Contact'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RelationshipChip extends StatelessWidget {
  final String label;
  final String value;
  final String selectedValue;
  final Function(String) onSelected;

  const _RelationshipChip({
    required this.label,
    required this.value,
    required this.selectedValue,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = value == selectedValue;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelected(value),
      selectedColor: AppTheme.primaryColor,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : null,
      ),
    );
  }
}
