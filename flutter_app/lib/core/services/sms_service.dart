import 'dart:io';
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
      // Normalize to keep digits and a leading "+" if present
      final normalized =
          phoneNumbers.map(_normalizePhoneForSms).where((p) => p.isNotEmpty).toList();
      if (normalized.isEmpty) {
        AppLogger.warning('No valid phone numbers for SMS');
        return false;
      }

      // Android prefers ";" as recipient separator; iOS is fine with ","
      final separator = Platform.isAndroid ? ';' : ',';
      final recipients = normalized.join(separator);

      // Create sms: URI with body
      final smsUri = Uri(
        scheme: 'sms',
        path: recipients,
        queryParameters: {'body': message},
      );

      // Launch the SMS app (no canLaunchUrl gate; can be blocked by package visibility)
      final launched = await launchUrl(
        smsUri,
        mode: LaunchMode.externalApplication,
      );
      if (launched) return true;

      // Fallback: try without body parameter
      final simpleSmsUri = Uri(
        scheme: 'sms',
        path: recipients,
      );
      return await launchUrl(
        simpleSmsUri,
        mode: LaunchMode.externalApplication,
      );
      AppLogger.warning('Could not launch SMS app');
      return false;
    } catch (e, stackTrace) {
      AppLogger.error('Error sending SMS', e, stackTrace);
      return false;
    }
  }

  String _normalizePhoneForSms(String phone) {
    final trimmed = phone.trim();
    final hasPlus = trimmed.startsWith('+');
    final digitsOnly = trimmed.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsOnly.isEmpty) return '';
    return hasPlus ? '+$digitsOnly' : digitsOnly;
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
  /// Returns bool indicating if SMS app was opened successfully (not actual message send)
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
  /// Returns count: 1 if app opened, 0 if failed or cancelled (not actual message count)
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
        // Remove all non-digit characters for wa.me URL (security: prevent URL injection)
        final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');

        // Validate phone number length (E.164 standard: min 10, max 15 digits)
        // Security: prevents overflow/injection attacks with malformed numbers
        if (cleanPhone.isEmpty ||
            cleanPhone.length < 10 ||
            cleanPhone.length > 15) {
          AppLogger.error('Invalid phone number format for WhatsApp sharing');
          return 0;
        }

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
            AppLogger.info('WhatsApp opened');
          } else {
            AppLogger.warning('Could not launch WhatsApp');
          }
        } catch (e) {
          AppLogger.error('Error launching WhatsApp', e);
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
            // Return 1 to indicate app was opened (user will select contacts)
            successCount = 1;
            AppLogger.info('WhatsApp opened - user will select contacts');
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
  /// Returns bool indicating if share chooser was opened
  Future<bool> shareLocationWithMoreApps({
    required LocationModel location,
  }) async {
    final locationText = _formatLocation(location);

    try {
      // Use share_plus to show native app chooser
      await Share.share(locationText);
      AppLogger.info('Location share chooser opened');
      return true;
    } catch (e, stackTrace) {
      AppLogger.error('Error opening share chooser', e, stackTrace);
      return false;
    }
  }

  /// Share location via Telegram
  /// Opens Telegram with location text, user selects contacts manually
  /// Tries tg:// app scheme first for faster loading, falls back to https://t.me/
  /// Returns count: 1 if app opened, 0 if failed or cancelled (not actual message count)
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

      // Try Telegram app scheme first (faster, doesn't open browser)
      Uri telegramUrl = Uri.parse('tg://msg?text=$message');

      try {
        // Check if Telegram app is available
        if (await canLaunchUrl(telegramUrl)) {
          final launched = await launchUrl(
            telegramUrl,
            mode: LaunchMode.externalApplication,
          );
          if (launched) {
            successCount = 1;
            AppLogger.info('Telegram app opened - user will select contacts');
            return successCount;
          }
        }
      } catch (e) {
        AppLogger.debug('Telegram app not available, falling back to web URL');
      }

      // Fallback to web URL if app is not available
      telegramUrl = Uri.parse('https://t.me/share/url?url=$message');

      try {
        final launched = await launchUrl(
          telegramUrl,
          mode: LaunchMode.externalApplication,
        );
        if (launched) {
          // Return 1 to indicate app/web was opened (user will select contacts)
          successCount = 1;
          AppLogger.info('Telegram web opened - user will select contacts');
        } else {
          AppLogger.warning('Could not launch Telegram');
        }
      } catch (e) {
        AppLogger.error('Error launching Telegram web', e);
      }
      return successCount;
    } catch (e) {
      AppLogger.error('Error sharing via Telegram', e);
      return successCount;
    }
  }
}
