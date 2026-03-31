import 'package:flutter/material.dart';
import '../../core/providers/password_breach_provider.dart';
import '../utils/validators.dart';

/// Widget to display password breach check status.
/// Includes accessibility support for screen readers.
class PasswordBreachIndicator extends StatelessWidget {
  final PasswordBreachCheckState state;
  final VoidCallback? onRetry;

  const PasswordBreachIndicator({
    super.key,
    required this.state,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _getAccessibilityLabel(),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _buildIndicator(context),
      ),
    );
  }

  Widget _buildIndicator(BuildContext context) {
    return switch (state.state) {
      PasswordBreachState.idle => const SizedBox.shrink(),
      PasswordBreachState.checking => _buildChecking(),
      PasswordBreachState.safe => _buildSafe(),
      PasswordBreachState.breached => _buildBreached(context),
      PasswordBreachState.offline => _buildOffline(),
      PasswordBreachState.error => _buildError(),
    };
  }

  Widget _buildChecking() {
    return Container(
      key: const ValueKey('checking'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              'Checking password security...',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSafe() {
    // Use semantic colors that work in both light and dark mode
    const safeColor = Color(0xFF2E7D32); // Green 800
    const safeBgColor = Color(0xFFE8F5E9); // Green 50
    const safeBorderColor = Color(0xFFA5D6A7); // Green 200

    return Container(
      key: const ValueKey('safe'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: safeBgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: safeBorderColor),
      ),
      child: const Row(
        children: [
          Icon(Icons.check_circle, color: safeColor, size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Password not found in known data breaches',
              style: TextStyle(color: safeColor, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreached(BuildContext context) {
    // Use semantic colors for warnings
    const warningColor = Color(0xFFF57C00); // Orange 700
    const warningDarkColor = Color(0xFFEF6C00); // Orange 800
    const warningBgColor = Color(0xFFFFF3E0); // Orange 50
    const warningBorderColor = Color(0xFFFFB74D); // Orange 300

    return Container(
      key: const ValueKey('breached'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warningBgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: warningBorderColor),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: warningColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Warning: Found in ${Validators.formatBreachCount(state.breachCount)} data breaches',
              style: const TextStyle(color: warningDarkColor, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOffline() {
    const greyColor = Color(0xFF757575); // Grey 600

    return Container(
      key: const ValueKey('offline'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, color: greyColor, size: 16),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              'Offline - security check skipped',
              style: TextStyle(color: greyColor, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    const greyColor = Color(0xFF757575); // Grey 600
    const linkColor = Color(0xFF1E88E5); // Blue 600

    return Container(
      key: const ValueKey('error'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.info_outline, color: greyColor, size: 16),
          const SizedBox(width: 8),
          const Flexible(
            child: Text(
              'Could not verify password security',
              style: TextStyle(color: greyColor, fontSize: 12),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onRetry,
              child: const Text(
                'Retry',
                style: TextStyle(
                  color: linkColor,
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getAccessibilityLabel() {
    return switch (state.state) {
      PasswordBreachState.idle => '',
      PasswordBreachState.checking => 'Checking password security',
      PasswordBreachState.safe => 'Password has not been found in known data breaches',
      PasswordBreachState.breached =>
        'Warning: Password found in ${Validators.formatBreachCount(state.breachCount)} data breaches',
      PasswordBreachState.offline => 'Offline: Cannot verify password security',
      PasswordBreachState.error => 'Could not verify password security',
    };
  }
}
