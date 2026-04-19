import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/utils/logger.dart';

/// Device-level preferences that need to outlive a single session but are
/// not sensitive (keep SharedPreferences, not SecureHive). Kept in one
/// provider so the Settings screen watches a single source of truth.
///
/// Sensitive data (auth, contacts, location history) still lives in
/// SecureHive — do not migrate any of that here.

const _kPrefix = 'app_pref_';
const _kThemeMode = '${_kPrefix}theme_mode';
const _kNotifSosSent = '${_kPrefix}notif_sos_sent';
const _kNotifLiveShare = '${_kPrefix}notif_live_share';
const _kNotifSyncErr = '${_kPrefix}notif_sync_err';

enum NotificationKind { sosSent, liveShareStarted, syncError }

class AppPreferencesState {
  final ThemeMode themeMode;
  final bool notifySosSent;
  final bool notifyLiveShareStarted;
  final bool notifySyncErrors;

  const AppPreferencesState({
    this.themeMode = ThemeMode.system,
    this.notifySosSent = true,
    this.notifyLiveShareStarted = true,
    this.notifySyncErrors = true,
  });

  AppPreferencesState copyWith({
    ThemeMode? themeMode,
    bool? notifySosSent,
    bool? notifyLiveShareStarted,
    bool? notifySyncErrors,
  }) {
    return AppPreferencesState(
      themeMode: themeMode ?? this.themeMode,
      notifySosSent: notifySosSent ?? this.notifySosSent,
      notifyLiveShareStarted:
          notifyLiveShareStarted ?? this.notifyLiveShareStarted,
      notifySyncErrors: notifySyncErrors ?? this.notifySyncErrors,
    );
  }
}

class AppPreferencesNotifier extends StateNotifier<AppPreferencesState> {
  AppPreferencesNotifier() : super(const AppPreferencesState()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      state = AppPreferencesState(
        themeMode: _themeFromString(prefs.getString(_kThemeMode)),
        notifySosSent: prefs.getBool(_kNotifSosSent) ?? true,
        notifyLiveShareStarted: prefs.getBool(_kNotifLiveShare) ?? true,
        notifySyncErrors: prefs.getBool(_kNotifSyncErr) ?? true,
      );
    } catch (e) {
      AppLogger.debug('AppPreferences load failed: $e');
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _write((prefs) => prefs.setString(_kThemeMode, _themeToString(mode)));
  }



  Future<void> setNotificationPref(NotificationKind kind, bool enabled) async {
    switch (kind) {
      case NotificationKind.sosSent:
        state = state.copyWith(notifySosSent: enabled);
        await _write((prefs) => prefs.setBool(_kNotifSosSent, enabled));
        break;
      case NotificationKind.liveShareStarted:
        state = state.copyWith(notifyLiveShareStarted: enabled);
        await _write((prefs) => prefs.setBool(_kNotifLiveShare, enabled));
        break;
      case NotificationKind.syncError:
        state = state.copyWith(notifySyncErrors: enabled);
        await _write((prefs) => prefs.setBool(_kNotifSyncErr, enabled));
        break;
    }
  }

  Future<void> _write(Future<void> Function(SharedPreferences) op) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await op(prefs);
    } catch (e) {
      AppLogger.debug('AppPreferences write failed: $e');
    }
  }

  static ThemeMode _themeFromString(String? v) {
    switch (v) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  static String _themeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}

final appPreferencesProvider =
    StateNotifierProvider<AppPreferencesNotifier, AppPreferencesState>(
  (ref) => AppPreferencesNotifier(),
);
