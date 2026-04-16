import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConstants {
  AppConstants._();

  // App Info
  static const String appName = 'SafetyApp';
  static const String appVersion = '1.0.0';

  // Default API endpoints (fallback if not configured in .env)
  static const String _defaultDevApiUrl = 'http://10.0.2.2:3001';
  static const String _defaultDevWsUrl = 'ws://10.0.2.2:3001';
  static const String _defaultProdApiUrl = 'https://api.safetyapp.com';
  static const String _defaultProdWsUrl = 'wss://api.safetyapp.com';

  // API Endpoints (Elysia Backend)
  // Load from .env file for security and flexibility
  static String get apiBaseUrl {
    final envUrl = dotenv.env['API_BASE_URL'];
    if (envUrl != null && envUrl.isNotEmpty) {
      return envUrl;
    }
    // Fallback to defaults based on build mode
    return kDebugMode ? _defaultDevApiUrl : _defaultProdApiUrl;
  }

  static String get wsBaseUrl {
    final envUrl = dotenv.env['WS_BASE_URL'];
    if (envUrl != null && envUrl.isNotEmpty) {
      return envUrl;
    }
    // Fallback to defaults based on build mode
    return kDebugMode ? _defaultDevWsUrl : _defaultProdWsUrl;
  }

  // Storage Keys
  static const String userBoxName = 'user_box';
  static const String contactsBoxName = 'contacts_box';
  static const String locationBoxName = 'location_box';
  static const String settingsBoxName = 'settings_box';
  static const String cachedUserKey = 'cached_user_json';

  // Location Settings
  // Use different intervals based on mode for battery efficiency
  static const int locationUpdateIntervalNormalMs = 60000;      // 1 min - normal mode
  static const int locationUpdateIntervalSharingMs = 15000;     // 15 sec - active sharing
  static const int locationUpdateIntervalEmergencyMs = 5000;    // 5 sec - SOS mode
  static const int locationDistanceFilterMeters = 50;           // Increased from 10m

  // Adaptive tracking (live location sharing)
  // Normal tier: 15s / 25m - default while actively sharing
  // Stationary tier: 60s / 0m - user hasn't moved much, back off
  // Emergency tier: 5s / 0m - SOS active, maximum freshness
  static const int liveSharingNormalDistanceFilterMeters = 25;
  static const int liveSharingStationaryDistanceFilterMeters = 0;
  static const int liveSharingEmergencyDistanceFilterMeters = 0;

  // Tier transition thresholds
  static const double kTierStationaryRadiusMeters = 25.0;   // max drift to be "stationary"
  static const Duration kTierWindow = Duration(minutes: 2); // look-back window
  static const double kTierExitMeters = 50.0;               // movement to exit stationary
  static const Duration kTierDebounce = Duration(seconds: 30);

  // Heartbeat + staleness
  static const Duration kHeartbeatInterval = Duration(seconds: 60);
  static const Duration kStaleThreshold = Duration(seconds: 60);

  // Battery sampler cache duration (avoid calling battery_plus on every position)
  static const Duration kBatterySampleInterval = Duration(seconds: 30);

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
