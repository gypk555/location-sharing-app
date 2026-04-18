import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';

class SafetyTipCard extends StatelessWidget {
  const SafetyTipCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppTheme.primaryColor.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb, color: AppTheme.primaryColor),
                const SizedBox(width: 8),
                Text(
                  'Safety Tip',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Shake your phone 3 times quickly to trigger an SOS alert. '
              'Make sure you have added emergency contacts.',
            ),
          ],
        ),
      ),
    );
  }
}
