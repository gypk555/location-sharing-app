import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_preferences_provider.dart';
import '../../../core/services/fake_call_service.dart' show FakeCallService;
import '../../../shared/theme/app_theme.dart';
import '../../../shared/utils/validators.dart';

enum FakeCallerField { name, number }

class FakeCallerDialog extends ConsumerStatefulWidget {
  final FakeCallerField focus;
  const FakeCallerDialog({super.key, required this.focus});

  @override
  ConsumerState<FakeCallerDialog> createState() => _FakeCallerDialogState();
}

class _FakeCallerDialogState extends ConsumerState<FakeCallerDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _numberCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // FakeCallService is hydrated from SharedPreferences in main.dart
    // before runApp, so it's the authoritative source at dialog-open
    // time. The provider may still be mid-`_load()` on a cold first
    // launch, which would briefly surface null fields.
    final service = FakeCallService();
    _nameCtrl = TextEditingController(text: service.callerName);
    _numberCtrl = TextEditingController(text: service.callerNumber);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _numberCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameCtrl.text.trim();
    final number = Validators.normalizePhone(_numberCtrl.text.trim());

    setState(() => _saving = true);

    await ref
        .read(appPreferencesProvider.notifier)
        .setFakeCaller(name: name, number: number);

    // Keep the singleton in sync so an already-scheduled call uses the new
    // values without requiring a restart.
    await FakeCallService().setCallerInfo(name, number);

    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Fake caller updated'),
        backgroundColor: AppTheme.successColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Fake Caller'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameCtrl,
              enabled: !_saving,
              autofocus: widget.focus == FakeCallerField.name,
              decoration: const InputDecoration(
                labelText: 'Caller Name',
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
                return null;
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _numberCtrl,
              enabled: !_saving,
              autofocus: widget.focus == FakeCallerField.number,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Caller Number',
                hintText: '+91XXXXXXXXXX',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              inputFormatters: [Validators.phoneInputFormatter],
              textInputAction: TextInputAction.done,
              validator: (value) {
                final v = value?.trim() ?? '';
                if (v.isEmpty) return 'Number cannot be empty';
                if (!Validators.isValidE164(Validators.normalizePhone(v))) {
                  return 'Use E.164 format, e.g. +919876543210';
                }
                return null;
              },
            ),
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
