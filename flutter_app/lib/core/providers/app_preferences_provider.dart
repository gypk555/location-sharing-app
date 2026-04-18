import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/sos_service.dart';
import '../../shared/utils/logger.dart';

/// Device-level preferences that need to outlive a single session but are
/// not sensitive (keep SharedPreferences, not SecureHive). Kept in one
/// provider so the Settings screen watches a single source of truth.
///
/// Sensitive data (auth, contacts, location history) still lives in
/// SecureHive — do not migrate any of that here.

const _kPrefix = 'app_pref_';
const _kThemeMode = '${_kPrefix}theme_mode';
const _kSosTemplate = '${_kPrefix}sos_template';
const _kFakeCallerName = '${_kPrefix}fake_caller_name';
const _kFakeCallerNumber = '${_kPrefix}fake_caller_number';
const _kNotifSosSent = '${_kPrefix}notif_sos_sent';
const _kNotifLiveShare = '${_kPrefix}notif_live_share';
const _kNotifSyncErr = '${_kPrefix}notif_sync_err';

/// Pref-keys exported so singleton services (SosService, FakeCallService)
/// can read the same values without threading Riverpod through them.
/// Keeping the constants in one file means a rename propagates via compile
/// error instead of a silent runtime drift.
const kSosTemplatePrefKey = _kSosTemplate;
const kFakeCallerNamePrefKey = _kFakeCallerName;
const kFakeCallerNumberPrefKey = _kFakeCallerNumber;

enum NotificationKind { sosSent, liveShareStarted, syncError }

class AppPreferencesState {
  final ThemeMode themeMode;
  final String? sosTemplateOverride;
  final String? fakeCallerName;
  final String? fakeCallerNumber;
  final bool notifySosSent;
  final bool notifyLiveShareStarted;
  final bool notifySyncErrors;

  const AppPreferencesState({
    this.themeMode = ThemeMode.system,
    this.sosTemplateOverride,
    this.fakeCallerName,
    this.fakeCallerNumber,
    this.notifySosSent = true,
    this.notifyLiveShareStarted = true,
    this.notifySyncErrors = true,
  });

  AppPreferencesState copyWith({
    ThemeMode? themeMode,
    String? sosTemplateOverride,
    bool clearSosTemplateOverride = false,
    String? fakeCallerName,
    String? fakeCallerNumber,
    bool? notifySosSent,
    bool? notifyLiveShareStarted,
    bool? notifySyncErrors,
  }) {
    return AppPreferencesState(
      themeMode: themeMode ?? this.themeMode,
      sosTemplateOverride: clearSosTemplateOverride
          ? null
          : (sosTemplateOverride ?? this.sosTemplateOverride),
      fakeCallerName: fakeCallerName ?? this.fakeCallerName,
      fakeCallerNumber: fakeCallerNumber ?? this.fakeCallerNumber,
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
        sosTemplateOverride: prefs.getString(_kSosTemplate),
        fakeCallerName: prefs.getString(_kFakeCallerName),
        fakeCallerNumber: prefs.getString(_kFakeCallerNumber),
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

  /// Pass null (or "") to clear the override and fall back to the built-in
  /// template in AppConstants.sosMessageTemplate.
  Future<void> setSosTemplateOverride(String? template) async {
    final normalized = (template == null || template.trim().isEmpty)
        ? null
        : template.trim();
    state = state.copyWith(
      sosTemplateOverride: normalized,
      clearSosTemplateOverride: normalized == null,
    );
    // Keep the singleton's hot-path cache in sync so the next SOS trigger
    // picks up the new template without re-reading SharedPreferences.
    SosService().updateSosTemplateOverride(normalized);
    await _write((prefs) {
      if (normalized == null) return prefs.remove(_kSosTemplate);
      return prefs.setString(_kSosTemplate, normalized);
    });
  }

  Future<void> setFakeCaller({String? name, String? number}) async {
    state = state.copyWith(
      fakeCallerName: name ?? state.fakeCallerName,
      fakeCallerNumber: number ?? state.fakeCallerNumber,
    );
    await _write((prefs) async {
      if (name != null) await prefs.setString(_kFakeCallerName, name);
      if (number != null) await prefs.setString(_kFakeCallerNumber, number);
    });
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
