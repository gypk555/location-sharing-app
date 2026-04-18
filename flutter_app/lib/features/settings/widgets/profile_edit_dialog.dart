import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/user_model.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/utils/validators.dart';

class ProfileEditDialog extends ConsumerStatefulWidget {
  final UserModel user;
  const ProfileEditDialog({super.key, required this.user});

  @override
  ConsumerState<ProfileEditDialog> createState() => _ProfileEditDialogState();
}

class _ProfileEditDialogState extends ConsumerState<ProfileEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.user.name ?? '');
    _phoneCtrl = TextEditingController(text: widget.user.phone ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final newName = _nameCtrl.text.trim();
    final newPhoneInput = _phoneCtrl.text.trim();

    final nameChanged = newName != (widget.user.name ?? '');
    final phoneChanged = newPhoneInput != (widget.user.phone ?? '');

    if (!nameChanged && !phoneChanged) {
      Navigator.pop(context);
      return;
    }

    setState(() => _saving = true);

    final ok = await ref.read(authStateProvider.notifier).updateProfile(
          name: nameChanged ? newName : null,
          phone: phoneChanged ? Validators.normalizePhone(newPhoneInput) : null,
        );

    if (!mounted) return;

    if (ok) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Profile updated'),
          backgroundColor: AppTheme.successColor,
        ),
      );
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = ref.watch(authStateProvider.select((s) => s.error));

    return AlertDialog(
      title: const Text('Edit Profile'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameCtrl,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Name',
                prefixIcon: Icon(Icons.person_outline),
              ),
              inputFormatters: [
                Validators.nameInputFormatter,
                Validators.noEmojiFormatter,
              ],
              maxLength: Validators.maxNameLength,
              textInputAction: TextInputAction.next,
              validator: (value) {
                final v = value?.trim() ?? '';
                if (v.isEmpty) return 'Name cannot be empty';
                if (v.length < 2) return 'Name is too short';
                return null;
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _phoneCtrl,
              enabled: !_saving,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone',
                hintText: '+91XXXXXXXXXX',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              inputFormatters: [Validators.phoneInputFormatter],
              textInputAction: TextInputAction.done,
              validator: (value) {
                final v = value?.trim() ?? '';
                if (v.isEmpty) return null; // phone is optional
                if (!Validators.isValidE164(Validators.normalizePhone(v))) {
                  return 'Use E.164 format, e.g. +919876543210';
                }
                return null;
              },
            ),
            if (error != null && !_saving) ...[
              const SizedBox(height: 12),
              Text(
                error,
                style: TextStyle(color: AppTheme.errorColor, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
