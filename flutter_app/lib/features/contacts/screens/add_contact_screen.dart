import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers/contacts_provider.dart';
import '../../../core/models/contact_model.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/utils/validators.dart';

class AddContactScreen extends ConsumerStatefulWidget {
  final ContactModel? contact;

  const AddContactScreen({super.key, this.contact});

  bool get isEditing => contact != null;

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
  bool _isSaving = false; // Prevent duplicate submissions

  @override
  void initState() {
    super.initState();
    // Pre-fill fields if editing
    if (widget.contact != null) {
      final c = widget.contact!;
      _nameController.text = c.name;
      _phoneController.text = c.phone;
      _emailController.text = c.email ?? '';
      _relationship = c.relationship ?? 'family';
      _isSosContact = c.isSosContact;
      _isLocationSharing = c.isLocationSharing;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _saveContact() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSaving) return; // Prevent duplicate submissions

    setState(() => _isSaving = true);

    try {
      final normalizedPhone = Validators.normalizePhone(_phoneController.text);
      final isEditing = widget.isEditing;

      final contact = ContactModel(
        id: isEditing ? widget.contact!.id : const Uuid().v4(),
        name: Validators.sanitizeName(_nameController.text),
        phone: normalizedPhone,
        email: _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim().toLowerCase(),
        relationship: _relationship,
        isSosContact: _isSosContact,
        isLocationSharing: _isLocationSharing,
        addedAt: isEditing ? widget.contact!.addedAt : DateTime.now(),
        userId: isEditing ? widget.contact!.userId : null,
        isPrimary: isEditing ? widget.contact!.isPrimary : false, // Preserve isPrimary status
        isSynced: false, // Mark as unsynced to trigger sync
      );

      if (isEditing) {
        await ref.read(contactsProvider.notifier).updateContact(contact);
      } else {
        await ref.read(contactsProvider.notifier).addContact(contact);
      }

      if (mounted) {
        // Check if operation failed by reading provider error state
        final error = ref.read(contactsProvider).error;
        if (error != null) {
          // Show error and stay on screen so user can fix the issue
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error),
              backgroundColor: Colors.red,
            ),
          );
          // Clear the error so it doesn't persist
          ref.read(contactsProvider.notifier).clearError();
          return; // Don't pop - let user fix the issue
        }

        // Success - show confirmation and close screen
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isEditing
                  ? '${contact.name} updated successfully'
                  : '${contact.name} added successfully',
            ),
          ),
        );
        context.pop();
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit Contact' : 'Add Contact'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveContact,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
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
              const Center(
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
                maxLength: Validators.maxNameLength,
                inputFormatters: [
                  Validators.nameInputFormatter,
                  Validators.noEmojiFormatter,
                ],
                decoration: const InputDecoration(
                  labelText: 'Name *',
                  prefixIcon: Icon(Icons.person),
                  counterText: '', // Hide character counter
                ),
                validator: Validators.validateName,
              ),

              const SizedBox(height: 16),

              // Phone
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                maxLength: Validators.maxPhoneLength,
                inputFormatters: [Validators.phoneInputFormatter],
                decoration: const InputDecoration(
                  labelText: 'Phone Number *',
                  prefixIcon: Icon(Icons.phone),
                  hintText: '+91 98765 43210',
                  helperText: 'Valid phone number is critical for SOS alerts',
                  counterText: '', // Hide character counter
                ),
                validator: Validators.validatePhone,
              ),

              const SizedBox(height: 16),

              // Email (optional)
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                maxLength: Validators.maxEmailLength,
                inputFormatters: [Validators.emailInputFormatter],
                decoration: const InputDecoration(
                  labelText: 'Email (optional)',
                  prefixIcon: Icon(Icons.email),
                  counterText: '', // Hide character counter
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
                onPressed: _isSaving ? null : _saveContact,
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(widget.isEditing ? 'Update Contact' : 'Save Contact'),
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
