import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Dialog presented before sharing a location — lets the user pick which
/// messaging app to use (WhatsApp / Messages / Telegram / system share sheet).
class AppChooserDialog extends StatelessWidget {
  final VoidCallback onWhatsApp;
  final VoidCallback onSms;
  final VoidCallback onTelegram;
  final VoidCallback onMore;

  const AppChooserDialog({
    super.key,
    required this.onWhatsApp,
    required this.onSms,
    required this.onTelegram,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Open with'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 200),
        child: SizedBox(
          width: double.maxFinite,
          child: GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: [
              _AppIcon(
                label: 'WhatsApp',
                icon: FontAwesomeIcons.whatsapp,
                color: const Color(0xFF25D366),
                onTap: onWhatsApp,
              ),
              _AppIcon(
                label: 'Messages',
                icon: FontAwesomeIcons.comment,
                color: const Color(0xFF0084FF),
                onTap: onSms,
              ),
              _AppIcon(
                label: 'Telegram',
                icon: FontAwesomeIcons.telegram,
                color: const Color(0xFF0088cc),
                onTap: onTelegram,
              ),
              _AppIcon(
                label: 'More',
                icon: FontAwesomeIcons.share,
                color: Colors.grey,
                onTap: onMore,
              ),
            ],
          ),
        ),
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

class _AppIcon extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _AppIcon({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: color,
              size: 32,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
