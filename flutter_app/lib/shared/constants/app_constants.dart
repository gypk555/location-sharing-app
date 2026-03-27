import 'package:flutter/foundation.dart';

class AppConstants {
  AppConstants._();

  // App Info
  static const String appName = 'SafetyApp';
  static const String appVersion = '1.0.0';

  // API Endpoints (Elysia Backend)
  // IMPORTANT: Use HTTPS in production for security
  static String get apiBaseUrl {
    if (kDebugMode) {
      // Local development - Android emulator
      return 'http://10.0.2.2:3001';
    }
    // Production - MUST use HTTPS
    return 'https://api.safetyapp.com';
  }

  static String get wsBaseUrl {
    if (kDebugMode) {
      return 'ws://10.0.2.2:3001';
    }
    return 'wss://api.safetyapp.com';
  }

  // Storage Keys
  static const String userBoxName = 'user_box';
  static const String contactsBoxName = 'contacts_box';
  static const String locationBoxName = 'location_box';
  static const String settingsBoxName = 'settings_box';

  // Location Settings
  static const int locationUpdateIntervalMs = 5000;
  static const int locationDistanceFilterMeters = 10;

  // SOS Settings
  static const int shakeThreshold = 15;
  static const int shakeCountToTrigger = 3;
  static const int shakeTimeWindowMs = 1000;

  // SMS Templates
  static const String sosMessageTemplate =
      'EMERGENCY! I need help. My current location: {location}. Please contact me immediately or call emergency services.';

  static const String locationShareTemplate =
      'My current location: {location}. Shared via SafetyApp.';
}
