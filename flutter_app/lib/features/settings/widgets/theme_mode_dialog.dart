import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_preferences_provider.dart';
import '../../../shared/theme/app_theme.dart';

String themeModeLabel(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return 'Light';
    case ThemeMode.dark:
      return 'Dark';
    case ThemeMode.system:
      return 'System default';
  }
}

class ThemeModeDialog extends ConsumerWidget {
  const ThemeModeDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(
      appPreferencesProvider.select((s) => s.themeMode),
    );

    return AlertDialog(
      title: const Text('Dark Mode'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: ThemeMode.values.map((mode) {
          final isSelected = mode == current;
          return ListTile(
            title: Text(themeModeLabel(mode)),
            leading: Icon(
              isSelected ? Icons.check_circle : Icons.circle_outlined,
              color: isSelected ? AppTheme.primaryColor : null,
            ),
            onTap: () async {
              await ref
                  .read(appPreferencesProvider.notifier)
                  .setThemeMode(mode);
              if (context.mounted) Navigator.pop(context);
            },
          );
        }).toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
