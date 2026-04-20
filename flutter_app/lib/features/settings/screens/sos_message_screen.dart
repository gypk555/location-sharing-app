import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/profile_settings_provider.dart';
import '../../../shared/constants/app_constants.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/utils/validators.dart';

class SosMessageScreen extends ConsumerStatefulWidget {
  const SosMessageScreen({super.key});

  @override
  ConsumerState<SosMessageScreen> createState() => _SosMessageScreenState();
}

class _SosMessageScreenState extends ConsumerState<SosMessageScreen> {
  late final TextEditingController _ctrl;
  String? _error;
  bool _saving = false;

  static const _placeholder = '{location}';

  @override
  void initState() {
    super.initState();
    final override = ref.read(profileSettingsProvider).sosSettings.sosMessage;
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

    final newOverride =
        sanitized == AppConstants.sosMessageTemplate ? null : sanitized;

    try {
      final currentSettings = ref.read(profileSettingsProvider).sosSettings;
      await ref
          .read(profileSettingsProvider.notifier)
          .updateSosSettings(currentSettings.copyWith(sosMessage: newOverride));

      if (!mounted) return;
      context.pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SOS message saved'),
          backgroundColor: AppTheme.successColor,
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetToDefault() async {
    if (_saving) return;
    setState(() {
      _ctrl.text = AppConstants.sosMessageTemplate;
      _error = null;
      _saving = true;
    });
    try {
      final currentSettings = ref.read(profileSettingsProvider).sosSettings;
      await ref
          .read(profileSettingsProvider.notifier)
          .updateSosSettings(currentSettings.copyWith(sosMessage: null));
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Reset failed: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SOS Message'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
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
                          Icon(Icons.message, color: AppTheme.primaryColor),
                          SizedBox(width: 12),
                          Text(
                            'Customize Message',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.2)),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline, size: 20, color: AppTheme.primaryColor),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Use $_placeholder — it will be automatically replaced with your live tracking link when an SOS is sent.',
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _ctrl,
                        enabled: !_saving,
                        maxLines: 5,
                        maxLength: 500,
                        decoration: InputDecoration(
                          labelText: 'Your Message',
                          alignLabelWithHint: true,
                          errorText: _error,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _saving ? null : _resetToDefault,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Reset to default'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.textSecondary,
                          ),
                        ),
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
    );
  }
}
