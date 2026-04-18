import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:disable_battery_optimization/disable_battery_optimization.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/utils/logger.dart';

/// Helper that manages OEM-specific battery-optimization prompts.
///
/// On India's dominant Android OEMs (Xiaomi/MIUI, Oppo/ColorOS, Vivo/FuntouchOS,
/// Realme, OnePlus/OxygenOS) the OS aggressively kills background services
/// unless the user has explicitly whitelisted the app in "Autostart",
/// "Battery saver", or "Background pop-up" settings. No amount of correct
/// code can survive this; the user must take manual action.
///
/// This service:
///   1. Detects the manufacturer on Android
///   2. Shows a one-time prompt the first time a user starts live sharing
///   3. Deep-links to battery-optimization settings as best-effort
///   4. Remembers that we've asked, so we don't nag on every start
class OemBatteryService {
  static const _prefsKeyHasPrompted = 'oem.battery.hasPrompted';
  static const _aggressiveOems = <String>{
    'xiaomi',
    'redmi',
    'poco',
    'oppo',
    'vivo',
    'realme',
    'oneplus',
  };

  // Shared across all OemBatteryService instances — the plugin holds a
  // platform channel and has no dispose, so creating one per instance
  // leaks native-side resources.
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  /// Returns true if the device is on an aggressive-kill OEM.
  Future<bool> isAggressiveOem() async {
    if (!Platform.isAndroid) return false;
    try {
      final info = await _deviceInfo.androidInfo;
      final mfr = info.manufacturer.toLowerCase();
      final brand = info.brand.toLowerCase();
      return _aggressiveOems.contains(mfr) || _aggressiveOems.contains(brand);
    } catch (e) {
      AppLogger.debug('OEM detection failed: $e');
      return false;
    }
  }

  /// Returns the lowercased manufacturer string, or null if non-Android / unknown.
  Future<String?> manufacturer() async {
    if (!Platform.isAndroid) return null;
    try {
      final info = await _deviceInfo.androidInfo;
      return info.manufacturer.toLowerCase();
    } catch (_) {
      return null;
    }
  }

  /// Whether the app is already exempt from battery optimizations.
  Future<bool> isBatteryOptimizationDisabled() async {
    if (!Platform.isAndroid) return true;
    try {
      return (await DisableBatteryOptimization.isBatteryOptimizationDisabled) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Whether we've already shown the one-time OEM prompt to this user.
  Future<bool> hasPromptedBefore() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKeyHasPrompted) ?? false;
  }

  Future<void> markPrompted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyHasPrompted, true);
  }

  /// Launch the system battery-optimization settings so the user can
  /// whitelist the app. Best-effort; some OEM builds silently ignore this.
  Future<void> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await DisableBatteryOptimization.showDisableBatteryOptimizationSettings();
    } catch (e) {
      AppLogger.error('Failed to open battery optimization settings', e);
    }
  }

  /// Launch the manufacturer-specific "autostart" settings where supported.
  /// On MIUI/ColorOS/FuntouchOS this is a separate setting from battery
  /// optimization and is the real cause of background kills.
  Future<void> openManufacturerAutoStartSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await DisableBatteryOptimization.showDisableManufacturerBatteryOptimizationSettings(
        "Autostart required",
        "To keep sharing your live location when the screen is off, please enable Autostart / Background pop-up for Safety in your phone settings.",
      );
    } catch (e) {
      AppLogger.error('Failed to open OEM autostart settings', e);
    }
  }
}
