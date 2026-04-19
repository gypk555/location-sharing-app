import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/profile_settings_provider.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/utils/validators.dart';

enum FakeCallerField { name, number }

class FakeCallerScreen extends ConsumerStatefulWidget {
  final FakeCallerField focus;
  const FakeCallerScreen({super.key, this.focus = FakeCallerField.name});

  @override
  ConsumerState<FakeCallerScreen> createState() => _FakeCallerScreenState();
}

class _FakeCallerScreenState extends ConsumerState<FakeCallerScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _numberCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final fakeCall = ref.read(profileSettingsProvider).fakeCallSettings;
    _nameCtrl = TextEditingController(text: fakeCall.callerName);
    _numberCtrl = TextEditingController(text: fakeCall.callerNumber);
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

    final currentSettings = ref.read(profileSettingsProvider).fakeCallSettings;
    await ref
        .read(profileSettingsProvider.notifier)
        .updateFakeCallSettings(currentSettings.copyWith(callerName: name, callerNumber: number));

    if (!mounted) return;
    context.pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Fake caller updated'),
        backgroundColor: AppTheme.successColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fake Caller Details'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.person_pin, color: AppTheme.secondaryColor),
                            SizedBox(width: 12),
                            Text(
                              'Caller Identity',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Configure the details of the incoming fake call to make it look realistic.',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 24),
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
                        const SizedBox(height: 16),
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
                ),
                const SizedBox(height: 32),
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Save Changes',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
