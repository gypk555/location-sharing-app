/**
 * Background Tasks Registration
 *
 * This file registers headless tasks for background location tracking
 * and scheduled SMS sending. It must be imported in index.js.
 */

import {AppRegistry, Platform} from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import Geolocation from 'react-native-geolocation-service';

// Storage keys
const SCHEDULED_SMS_CONFIG_KEY = '@scheduled_sms_config';
const LAST_SCHEDULED_SMS_KEY = '@last_scheduled_sms';
const EMERGENCY_CONTACTS_KEY = '@emergency_contacts';
const AUTO_FALLBACK_ENABLED_KEY = '@auto_fallback_enabled';

/**
 * Configuration for scheduled SMS
 */
interface ScheduledSmsConfig {
  enabled: boolean;
  intervalMinutes: number;
  contacts: Array<{phone: string; name: string}>;
  includeGoogleMapsLink: boolean;
  includeRawCoordinates: boolean;
  includeAccuracyInfo: boolean;
}

/**
 * Get current location using Geolocation API
 */
async function getCurrentLocation(): Promise<{
  latitude: number;
  longitude: number;
  accuracy: number;
  timestamp: Date;
} | null> {
  return new Promise(resolve => {
    Geolocation.getCurrentPosition(
      position => {
        resolve({
          latitude: position.coords.latitude,
          longitude: position.coords.longitude,
          accuracy: position.coords.accuracy,
          timestamp: new Date(position.timestamp),
        });
      },
      error => {
        console.error('Background location error:', error);
        resolve(null);
      },
      {
        enableHighAccuracy: true,
        timeout: 30000,
        maximumAge: 10000,
      },
    );
  });
}

/**
 * Format location for SMS
 */
function formatLocationForSms(
  location: {
    latitude: number;
    longitude: number;
    accuracy: number;
    timestamp: Date;
  },
  config: ScheduledSmsConfig,
): string {
  const lines: string[] = [];

  if (config.includeGoogleMapsLink) {
    const lat = location.latitude.toFixed(6);
    const lng = location.longitude.toFixed(6);
    lines.push(`Location: https://maps.google.com/?q=${lat},${lng}`);
    lines.push('');
  }

  if (config.includeRawCoordinates) {
    lines.push(
      `Coordinates: ${location.latitude.toFixed(6)}, ${location.longitude.toFixed(6)}`,
    );
  }

  if (config.includeAccuracyInfo) {
    lines.push(`Accuracy: ~${Math.round(location.accuracy)}m`);
  }

  lines.push(`Time: ${location.timestamp.toLocaleString()}`);
  lines.push('');
  lines.push('- Scheduled update');

  return lines.join('\n');
}

/**
 * Headless task for scheduled SMS
 * This runs even when the app is killed (Android)
 */
async function scheduledSmsHeadlessTask(): Promise<void> {
  console.log('[BackgroundTask] Scheduled SMS task started');

  try {
    // Load config
    const configStr = await AsyncStorage.getItem(SCHEDULED_SMS_CONFIG_KEY);
    if (!configStr) {
      console.log('[BackgroundTask] No scheduled SMS config found');
      return;
    }

    const config: ScheduledSmsConfig = JSON.parse(configStr);
    if (!config.enabled || !config.contacts.length) {
      console.log('[BackgroundTask] Scheduled SMS disabled or no contacts');
      return;
    }

    // Check if enough time has passed
    const lastSmsStr = await AsyncStorage.getItem(LAST_SCHEDULED_SMS_KEY);
    if (lastSmsStr) {
      const lastTime = parseInt(lastSmsStr, 10);
      const intervalMs = config.intervalMinutes * 60 * 1000;
      if (Date.now() - lastTime < intervalMs) {
        console.log('[BackgroundTask] Too soon for scheduled SMS');
        return;
      }
    }

    // Get location
    const location = await getCurrentLocation();
    if (!location) {
      console.log('[BackgroundTask] Could not get location');
      return;
    }

    // Format message
    const message = formatLocationForSms(location, config);

    // Send SMS (this will only work on Android with SEND_SMS permission)
    if (Platform.OS === 'android') {
      const {NativeModules} = require('react-native');
      const {SmsModule} = NativeModules;

      if (SmsModule && SmsModule.sendDirectSms) {
        const phones = config.contacts.map(c => c.phone).join(',');
        await SmsModule.sendDirectSms(phones, message);
        console.log('[BackgroundTask] Scheduled SMS sent successfully');
      }
    }

    // Update last sent time
    await AsyncStorage.setItem(LAST_SCHEDULED_SMS_KEY, Date.now().toString());
  } catch (error) {
    console.error('[BackgroundTask] Scheduled SMS error:', error);
  }
}

/**
 * Headless task for auto-fallback SMS when offline
 */
async function offlineFallbackHeadlessTask(data: {
  offlineDurationMs: number;
}): Promise<void> {
  console.log('[BackgroundTask] Offline fallback task started');

  try {
    // Check if auto-fallback is enabled
    const enabled = await AsyncStorage.getItem(AUTO_FALLBACK_ENABLED_KEY);
    if (enabled !== 'true') {
      console.log('[BackgroundTask] Auto-fallback disabled');
      return;
    }

    // Load emergency contacts (or fallback contacts)
    const contactsStr = await AsyncStorage.getItem(EMERGENCY_CONTACTS_KEY);
    if (!contactsStr) {
      console.log('[BackgroundTask] No emergency contacts configured');
      return;
    }

    const contacts = JSON.parse(contactsStr);
    if (!contacts.length) {
      return;
    }

    // Get location
    const location = await getCurrentLocation();
    if (!location) {
      console.log('[BackgroundTask] Could not get location for fallback');
      return;
    }

    // Format message
    const lat = location.latitude.toFixed(6);
    const lng = location.longitude.toFixed(6);
    const message = [
      'Auto Location Update (Offline)',
      '',
      `Location: https://maps.google.com/?q=${lat},${lng}`,
      '',
      `Coordinates: ${lat}, ${lng}`,
      `Accuracy: ~${Math.round(location.accuracy)}m`,
      `Time: ${location.timestamp.toLocaleString()}`,
      `Offline for: ${Math.round(data.offlineDurationMs / 1000)}s`,
      '',
      '- Sent automatically (no internet)',
    ].join('\n');

    // Send SMS
    if (Platform.OS === 'android') {
      const {NativeModules} = require('react-native');
      const {SmsModule} = NativeModules;

      if (SmsModule && SmsModule.sendDirectSms) {
        const phones = contacts.map((c: any) => c.phone).join(',');
        await SmsModule.sendDirectSms(phones, message);
        console.log('[BackgroundTask] Offline fallback SMS sent');
      }
    }
  } catch (error) {
    console.error('[BackgroundTask] Offline fallback error:', error);
  }
}

// Register headless tasks (Android only)
if (Platform.OS === 'android') {
  // Note: These need to be registered with the native background task libraries
  // For now, we export them for use with BackgroundFetch
  AppRegistry.registerHeadlessTask(
    'ScheduledSmsTask',
    () => scheduledSmsHeadlessTask,
  );

  AppRegistry.registerHeadlessTask(
    'OfflineFallbackTask',
    () => offlineFallbackHeadlessTask,
  );
}

export {scheduledSmsHeadlessTask, offlineFallbackHeadlessTask};

// Storage helper functions
export async function saveScheduledSmsConfig(
  config: ScheduledSmsConfig,
): Promise<void> {
  await AsyncStorage.setItem(SCHEDULED_SMS_CONFIG_KEY, JSON.stringify(config));
}

export async function getScheduledSmsConfig(): Promise<ScheduledSmsConfig | null> {
  const str = await AsyncStorage.getItem(SCHEDULED_SMS_CONFIG_KEY);
  return str ? JSON.parse(str) : null;
}

export async function setAutoFallbackEnabled(enabled: boolean): Promise<void> {
  await AsyncStorage.setItem(AUTO_FALLBACK_ENABLED_KEY, enabled.toString());
}

export async function getAutoFallbackEnabled(): Promise<boolean> {
  const str = await AsyncStorage.getItem(AUTO_FALLBACK_ENABLED_KEY);
  return str === 'true';
}
