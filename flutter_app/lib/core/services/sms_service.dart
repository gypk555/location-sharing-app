import 'package:url_launcher/url_launcher.dart';
import '../models/location_model.dart';
import '../models/contact_model.dart';
import '../../shared/constants/app_constants.dart';

class SmsService {
  static final SmsService _instance = SmsService._internal();
  factory SmsService() => _instance;
  SmsService._internal();

  /// Send SOS alert to emergency contacts via SMS
  Future<bool> sendSosAlert({
    required List<ContactModel> contacts,
    required LocationModel location,
    String? customMessage,
  }) async {
    if (contacts.isEmpty) {
      return false;
    }

    final locationText = _formatLocation(location);
    final message = customMessage ??
        AppConstants.sosMessageTemplate.replaceAll('{location}', locationText);

    final phoneNumbers =
        contacts.where((c) => c.isSosContact).map((c) => c.phone).toList();

    if (phoneNumbers.isEmpty) {
      return false;
    }

    return await _sendSms(phoneNumbers, message);
  }

  /// Send location share to contacts
  Future<bool> sendLocationShare({
    required List<ContactModel> contacts,
    required LocationModel location,
  }) async {
    final phoneNumbers =
        contacts.where((c) => c.isLocationSharing).map((c) => c.phone).toList();

    if (phoneNumbers.isEmpty) return false;

    final locationText = _formatLocation(location);
    final message =
        AppConstants.locationShareTemplate.replaceAll('{location}', locationText);

    return await _sendSms(phoneNumbers, message);
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

  /// Send bulk SMS to multiple recipients (opens SMS app for each)
  Future<int> sendBulkSms({
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
}
