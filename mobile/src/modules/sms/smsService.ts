import {Linking, Platform, NativeModules} from 'react-native';
import {LocationData} from '../location/LocationContext';

export interface SmsRecipient {
  phone: string;
  name: string;
}

export interface SmsOptions {
  includeGoogleMapsLink: boolean;
  includeRawCoordinates: boolean;
  includeAccuracyInfo: boolean;
  includeTimestamp: boolean;
  includeSpeed: boolean;
  customMessage?: string;
}

export type SmsMessageType = 'manual' | 'auto_fallback' | 'sos' | 'scheduled';

export interface SmsSendResult {
  success: boolean;
  error?: string;
}

// Default SMS options
export const defaultSmsOptions: SmsOptions = {
  includeGoogleMapsLink: true,
  includeRawCoordinates: true,
  includeAccuracyInfo: true,
  includeTimestamp: true,
  includeSpeed: true,
};

/**
 * Format location data into an SMS message
 */
export function formatLocationMessage(
  location: LocationData,
  options: SmsOptions = defaultSmsOptions,
): string {
  const lines: string[] = [];

  // Custom message if provided
  if (options.customMessage) {
    lines.push(options.customMessage);
    lines.push('');
  }

  // Google Maps link (preferred format)
  if (options.includeGoogleMapsLink) {
    const lat = location.latitude.toFixed(6);
    const lng = location.longitude.toFixed(6);
    const mapsLink = `https://maps.google.com/?q=${lat},${lng}`;
    lines.push(`Location: ${mapsLink}`);
    lines.push('');
  }

  // Raw coordinates
  if (options.includeRawCoordinates) {
    lines.push(
      `Coordinates: ${location.latitude.toFixed(6)}, ${location.longitude.toFixed(6)}`,
    );
  }

  // Accuracy info
  if (options.includeAccuracyInfo) {
    lines.push(`Accuracy: ~${Math.round(location.accuracy)}m`);
  }

  // Timestamp
  if (options.includeTimestamp) {
    const time = location.timestamp.toLocaleString();
    lines.push(`Time: ${time}`);
  }

  // Speed (if moving)
  if (
    options.includeSpeed &&
    location.speed !== undefined &&
    location.speed > 0
  ) {
    const speedKmh = (location.speed * 3.6).toFixed(1);
    lines.push(`Speed: ${speedKmh} km/h`);
  }

  return lines.join('\n');
}

/**
 * Format SOS emergency message
 */
export function formatSosMessage(
  location: LocationData,
  senderName?: string,
  customMessage?: string,
): string {
  const lines: string[] = [];

  // Emergency header
  lines.push('!!! EMERGENCY SOS !!!');
  lines.push('');

  // Sender name
  if (senderName) {
    lines.push(`From: ${senderName}`);
    lines.push('');
  }

  // Custom message or default
  if (customMessage) {
    lines.push(customMessage);
  } else {
    lines.push('I need help! This is my current location:');
  }
  lines.push('');

  // Google Maps link (always include for SOS)
  const lat = location.latitude.toFixed(6);
  const lng = location.longitude.toFixed(6);
  const mapsLink = `https://maps.google.com/?q=${lat},${lng}`;
  lines.push(`LOCATION: ${mapsLink}`);
  lines.push('');

  // Raw coordinates (always include for SOS)
  lines.push(`Coordinates: ${lat}, ${lng}`);
  lines.push(`Accuracy: ~${Math.round(location.accuracy)}m`);
  lines.push(`Time: ${location.timestamp.toLocaleString()}`);
  lines.push('');

  // Footer
  lines.push('- Sent via Location Sharing App');

  return lines.join('\n');
}

/**
 * Send SMS via native compose (opens SMS app)
 * Works on both iOS and Android
 */
export async function sendSmsViaCompose(
  recipients: SmsRecipient[],
  message: string,
): Promise<SmsSendResult> {
  try {
    const phones = recipients.map(r => r.phone).join(',');

    const url = Platform.select({
      ios: `sms:${phones}&body=${encodeURIComponent(message)}`,
      android: `sms:${phones}?body=${encodeURIComponent(message)}`,
    });

    if (!url) {
      return {success: false, error: 'Platform not supported'};
    }

    const canOpen = await Linking.canOpenURL(url);
    if (!canOpen) {
      return {success: false, error: 'Cannot open SMS app'};
    }

    await Linking.openURL(url);
    return {success: true};
  } catch (error: any) {
    return {success: false, error: error.message || 'Failed to open SMS'};
  }
}

/**
 * Send SMS directly (Android only, requires SEND_SMS permission)
 * Returns false if not available, falls back to compose
 */
export async function sendSmsDirectly(
  recipients: SmsRecipient[],
  message: string,
): Promise<SmsSendResult> {
  if (Platform.OS !== 'android') {
    // iOS doesn't support direct SMS, use compose
    return sendSmsViaCompose(recipients, message);
  }

  try {
    const {SmsModule} = NativeModules;

    if (!SmsModule || !SmsModule.sendDirectSms) {
      // Native module not available, fall back to compose
      console.log('SmsModule not available, using compose');
      return sendSmsViaCompose(recipients, message);
    }

    // Check permission
    const hasPermission = await SmsModule.checkSmsPermission();
    if (!hasPermission) {
      console.log('SMS permission not granted, using compose');
      return sendSmsViaCompose(recipients, message);
    }

    // Send directly
    const phones = recipients.map(r => r.phone).join(',');
    await SmsModule.sendDirectSms(phones, message);
    return {success: true};
  } catch (error: any) {
    console.error('Direct SMS failed:', error);
    // Fall back to compose on any error
    return sendSmsViaCompose(recipients, message);
  }
}

/**
 * Main function to share location via SMS
 */
export async function shareLocationViaSms(
  location: LocationData,
  recipients: SmsRecipient[],
  options: SmsOptions = defaultSmsOptions,
  messageType: SmsMessageType = 'manual',
): Promise<SmsSendResult> {
  if (recipients.length === 0) {
    return {success: false, error: 'No recipients specified'};
  }

  const message = formatLocationMessage(location, options);

  // For auto_fallback and scheduled, try direct SMS first (Android)
  // For manual, always use compose to let user confirm
  if (messageType === 'auto_fallback' || messageType === 'scheduled') {
    return sendSmsDirectly(recipients, message);
  }

  return sendSmsViaCompose(recipients, message);
}

/**
 * Send SOS emergency SMS
 */
export async function sendSosAlert(
  location: LocationData,
  recipients: SmsRecipient[],
  senderName?: string,
  customMessage?: string,
): Promise<SmsSendResult> {
  if (recipients.length === 0) {
    return {success: false, error: 'No emergency contacts configured'};
  }

  const message = formatSosMessage(location, senderName, customMessage);

  // SOS always tries direct send first for urgency
  return sendSmsDirectly(recipients, message);
}
