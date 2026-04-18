import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_preferences_provider.dart';
import '../../../shared/constants/app_constants.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/utils/validators.dart';

class SosMessageDialog extends ConsumerStatefulWidget {
  const SosMessageDialog({super.key});

  @override
  ConsumerState<SosMessageDialog> createState() => _SosMessageDialogState();
}

class _SosMessageDialogState extends ConsumerState<SosMessageDialog> {
  late final TextEditingController _ctrl;
  String? _error;
  bool _saving = false;

  static const _placeholder = '{location}';

  @override
  void initState() {
    super.initState();
    final override = ref.read(appPreferencesProvider).sosTemplateOverride;
    _ctrl = TextEditingController(
      text: override ?? AppConstants.sosMessageTemplate,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final raw = _ctrl.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'Message cannot be empty');
      return;
    }
    if (!raw.contains(_placeholder)) {
      setState(() => _error =
          'Message must include $_placeholder so your location is inserted');
      return;
    }

    // Strip control chars / null bytes before storing; this matches the
    // treatment that Validators applies to any user-authored text that
    // could end up in the SMS body.
    final sanitized = Validators.sanitizeForDatabase(raw);
    final securityError =
        Validators.validateSecureInput(sanitized, fieldName: 'SOS message');
    if (securityError != null) {
      setState(() => _error = securityError);
      return;
    }

    setState(() {
      _error = null;
      _saving = true;
    });

    // If the user typed the built-in default verbatim, clear the override
    // so future changes to the default propagate automatically.
    final newOverride =
        sanitized == AppConstants.sosMessageTemplate ? null : sanitized;

    await ref
        .read(appPreferencesProvider.notifier)
        .setSosTemplateOverride(newOverride);

    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('SOS message saved'),
        backgroundColor: AppTheme.successColor,
      ),
    );
  }

  Future<void> _resetToDefault() async {
    if (_saving) return;
    setState(() {
      _ctrl.text = AppConstants.sosMessageTemplate;
      _error = null;
      _saving = true;
    });
    await ref
        .read(appPreferencesProvider.notifier)
        .setSosTemplateOverride(null);
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('SOS Message'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Use $_placeholder — it will be replaced with your live '
              'location when an SOS is sent.',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              enabled: !_saving,
              maxLines: 5,
              maxLength: 500,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _saving ? null : _resetToDefault,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reset to default'),
              ),
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
