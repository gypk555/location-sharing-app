import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../models/location_model.dart';
import '../models/contact_model.dart';
import '../../shared/constants/app_constants.dart';
import '../../shared/utils/logger.dart';

class SmsService {
  static final SmsService _instance = SmsService._internal();
  factory SmsService() => _instance;
  SmsService._internal();

  /// Send SOS alert to emergency contacts via SMS
  /// Returns the number of successful sends
  Future<int> sendSosAlert({
    required List<ContactModel> contacts,
    required LocationModel location,
    String? customMessage,
  }) async {
    if (contacts.isEmpty) {
      return 0;
    }

    final locationText = _formatLocation(location);
    final message = customMessage ??
        AppConstants.sosMessageTemplate.replaceAll('{location}', locationText);

    final phoneNumbers =
        contacts.where((c) => c.isSosContact).map((c) => c.phone).toList();

    if (phoneNumbers.isEmpty) {
      return 0;
    }

    // Send one SMS at a time to ensure delivery on all Android versions
    return await _sendBulkSms(
      phoneNumbers: phoneNumbers,
      message: message,
    );
  }

  /// Send location share to contacts
  /// Returns the number of successful sends
  Future<int> sendLocationShare({
    required List<ContactModel> contacts,
    required LocationModel location,
  }) async {
    final phoneNumbers =
        contacts.where((c) => c.isLocationSharing).map((c) => c.phone).toList();

    if (phoneNumbers.isEmpty) return 0;

    final locationText = _formatLocation(location);
    final message =
        AppConstants.locationShareTemplate.replaceAll('{location}', locationText);

    // Send one SMS at a time to ensure delivery on all Android versions
    return await _sendBulkSms(
      phoneNumbers: phoneNumbers,
      message: message,
    );
  }

  /// Send SMS using url_launcher (opens default SMS app)
  Future<bool> _sendSms(List<String> phoneNumbers, String message) async {
    try {
      // Join multiple phone numbers with comma (some SMS apps support this)
      final recipients = phoneNumbers.join(',');

      // Encode the message for URL
      final encodedMessage = Uri.encodeComponent(message);

      // Create sms: URI
      final smsUri = Uri.parse('sms:$recipients?body=$encodedMessage');

      // Launch the SMS app
      if (await canLaunchUrl(smsUri)) {
        final launched = await launchUrl(smsUri);
        return launched;
      } else {
        // Fallback: try without body parameter (some platforms)
        final simpleSmsUri = Uri.parse('sms:$recipients');
        if (await canLaunchUrl(simpleSmsUri)) {
          return await launchUrl(simpleSmsUri);
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Format location for SMS message
  String _formatLocation(LocationModel location) {
    final buffer = StringBuffer();

    if (location.address != null && location.address!.isNotEmpty) {
      buffer.writeln(location.address);
    }

    buffer.write(location.googleMapsUrl);

    return buffer.toString();
  }

  /// Send a custom SMS to a single recipient
  Future<bool> sendCustomSms({
    required String phone,
    required String message,
  }) async {
    return await _sendSms([phone], message);
  }

  /// Send bulk SMS to multiple recipients (sends one SMS at a time)
  /// Opens SMS app for each contact to ensure delivery on all Android versions
  Future<int> _sendBulkSms({
    required List<String> phoneNumbers,
    required String message,
  }) async {
    int successCount = 0;
    for (final phone in phoneNumbers) {
      final success = await _sendSms([phone], message);
      if (success) successCount++;
    }
    return successCount;
  }

  /// Share location via SMS (pre-fills all phone numbers at once)
  Future<bool> shareLocationViaSms({
    required List<ContactModel> contacts,
    required LocationModel location,
  }) async {
    final sharingContacts = contacts.where((c) => c.isLocationSharing).toList();
    if (sharingContacts.isEmpty) {
      return false;
    }

    final phoneNumbers = sharingContacts.map((c) => c.phone).toList();
    final locationText = _formatLocation(location);

    return await _sendSms(phoneNumbers, locationText);
  }

  /// Share location via WhatsApp
  /// For single contact: opens WhatsApp with pre-filled number and message
  /// For multiple contacts: opens WhatsApp and user selects contacts manually
  Future<int> shareLocationViaWhatsApp({
    required List<ContactModel> contacts,
    required LocationModel location,
  }) async {
    final sharingContacts = contacts.where((c) => c.isLocationSharing).toList();
    if (sharingContacts.isEmpty) {
      return 0;
    }

    final locationText = _formatLocation(location);
    int successCount = 0;

    try {
      // For single contact: use direct wa.me link with pre-filled message
      if (sharingContacts.length == 1) {
        final contact = sharingContacts.first;
        final phoneNumber = contact.phone;
        final cleanPhone = phoneNumber.replaceAll('+', '').replaceAll(' ', '');
        final message = Uri.encodeComponent(locationText);

        // WhatsApp URL: https://wa.me/PHONENUMBER?text=MESSAGE
        final whatsappUrl = Uri.parse('https://wa.me/$cleanPhone?text=$message');

        try {
          final launched = await launchUrl(
            whatsappUrl,
            mode: LaunchMode.externalApplication,
          );
          if (launched) {
            successCount++;
            AppLogger.info('WhatsApp opened for $phoneNumber');
          } else {
            AppLogger.warning('Could not launch WhatsApp for $phoneNumber');
          }
        } catch (e) {
          AppLogger.error('Error launching WhatsApp for $phoneNumber', e);
        }
      } else {
        // For multiple contacts: open WhatsApp with location text, user selects contacts
        final message = Uri.encodeComponent(locationText);
        final whatsappUrl = Uri.parse('https://wa.me/?text=$message');

        try {
          final launched = await launchUrl(
            whatsappUrl,
            mode: LaunchMode.externalApplication,
          );
          if (launched) {
            // Return number of contacts for consistency
            successCount = sharingContacts.length;
            AppLogger.info('WhatsApp opened for ${sharingContacts.length} contacts');
          } else {
            AppLogger.warning('Could not launch WhatsApp');
          }
        } catch (e) {
          AppLogger.error('Error launching WhatsApp', e);
        }
      }
      return successCount;
    } catch (e) {
      AppLogger.error('Error sharing via WhatsApp', e);
      return successCount;
    }
  }

  /// Share location with other apps using native app chooser
  Future<bool> shareLocationWithMoreApps({
    required List<ContactModel> contacts,
    required LocationModel location,
  }) async {
    final sharingContacts = contacts.where((c) => c.isLocationSharing).toList();
    if (sharingContacts.isEmpty) {
      return false;
    }

    final locationText = _formatLocation(location);

    try {
      // Use share_plus to show native app chooser
      await Share.share(locationText);

      AppLogger.info('Share chooser opened for other apps');
      return true;
    } catch (e) {
      AppLogger.error('Error opening share chooser', e);
      return false;
    }
  }

  /// Share location via Telegram
  /// Opens Telegram with location text, user selects contacts manually
  Future<int> shareLocationViaTelegram({
    required List<ContactModel> contacts,
    required LocationModel location,
  }) async {
    final sharingContacts = contacts.where((c) => c.isLocationSharing).toList();
    if (sharingContacts.isEmpty) {
      return 0;
    }

    final locationText = _formatLocation(location);
    int successCount = 0;

    try {
      // Open Telegram with location text via share URL
      final message = Uri.encodeComponent(locationText);

      // Try Telegram's share URL format
      final telegramUrl = Uri.parse('https://t.me/share/url?url=$message');

      try {
        final launched = await launchUrl(
          telegramUrl,
          mode: LaunchMode.externalApplication,
        );
        if (launched) {
          // Return number of contacts since user will select them in Telegram
          successCount = sharingContacts.length;
          AppLogger.info('Telegram opened for ${sharingContacts.length} contacts');
        } else {
          AppLogger.warning('Could not launch Telegram');
        }
      } catch (e) {
        AppLogger.error('Error launching Telegram', e);
      }
      return successCount;
    } catch (e) {
      AppLogger.error('Error sharing via Telegram', e);
      return successCount;
    }
  }
}
