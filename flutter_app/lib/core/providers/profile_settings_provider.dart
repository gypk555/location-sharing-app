import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/utils/logger.dart';
import '../models/profile_settings_models.dart';
import '../services/profile_settings_service.dart';
import '../services/sos_service.dart';
import '../services/fake_call_service.dart';
import 'auth_provider.dart';

class ProfileSettingsState {
  final SosSettings sosSettings;
  final FakeCallSettings fakeCallSettings;
  final String? name;
  final String? phone;
  final bool isLoading;
  final String? error;

  const ProfileSettingsState({
    this.sosSettings = const SosSettings(),
    this.fakeCallSettings = const FakeCallSettings(),
    this.name,
    this.phone,
    this.isLoading = false,
    this.error,
  });

  ProfileSettingsState copyWith({
    SosSettings? sosSettings,
    FakeCallSettings? fakeCallSettings,
    String? name,
    String? phone,
    bool? isLoading,
    String? error,
  }) {
    return ProfileSettingsState(
      sosSettings: sosSettings ?? this.sosSettings,
      fakeCallSettings: fakeCallSettings ?? this.fakeCallSettings,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      isLoading: isLoading ?? this.isLoading,
      error: error, // overwrite error to null if not provided or clear it
    );
  }
}

class ProfileSettingsNotifier extends StateNotifier<ProfileSettingsState> {
  final Ref _ref;
  final ProfileSettingsService _service;

  ProfileSettingsNotifier(this._ref, this._service)
      : super(const ProfileSettingsState()) {
    _init();
  }

  Future<void> _init() async {
    final authState = _ref.read(authStateProvider);
    final userId = authState.user?.id;
    if (userId == null) return;

    state = state.copyWith(isLoading: true, error: null);

    try {
      final data = await _service.fetchProfileSettings(userId);
      final sosSettings = SosSettings.fromJson(data['sos_settings']);
      final fakeCallSettings = FakeCallSettings.fromJson(data['fake_call_settings']);
      
      state = state.copyWith(
        sosSettings: sosSettings,
        fakeCallSettings: fakeCallSettings,
        name: data['name'],
        phone: data['phone'],
        isLoading: false,
      );

      _syncToInMemoryServices(sosSettings, fakeCallSettings);
      _cacheToPrefs(sosSettings, fakeCallSettings);
    } catch (e) {
      AppLogger.error('ProfileSettingsNotifier: Fetch failed', e);
      // Offline fallback
      await _loadFromPrefs();
      state = state.copyWith(isLoading: false, error: 'Offline mode');
    }
  }

  void _syncToInMemoryServices(SosSettings sos, FakeCallSettings fake) {
    // SosService needs the shake alert and template
    // SosService().setShakeEnabled(sos.shakeAlertEnabled); // We need to make sure this doesn't loop back to provider
    // Actually, we'll see SosService's changes later. Let's just update template
    SosService().updateSosTemplateOverride(sos.sosMessage);
    
    // FakeCallService needs name and number
    FakeCallService().updateCallerInfo(fake.callerName, fake.callerNumber);
  }

  Future<void> _cacheToPrefs(SosSettings sos, FakeCallSettings fake) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cache_sos_settings', jsonEncode(sos.toJson()));
    await prefs.setString('cache_fake_call_settings', jsonEncode(fake.toJson()));
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final sosJson = prefs.getString('cache_sos_settings');
    final fakeJson = prefs.getString('cache_fake_call_settings');

    SosSettings sos = const SosSettings();
    if (sosJson != null) {
      sos = SosSettings.fromJson(jsonDecode(sosJson));
    }

    FakeCallSettings fake = const FakeCallSettings();
    if (fakeJson != null) {
      fake = FakeCallSettings.fromJson(jsonDecode(fakeJson));
    }

    state = state.copyWith(
      sosSettings: sos,
      fakeCallSettings: fake,
    );
    _syncToInMemoryServices(sos, fake);
  }

  Future<void> updateSosSettings(SosSettings newSettings) async {
    final userId = _ref.read(authStateProvider).user?.id;
    if (userId == null) return;

    final validationError = newSettings.validate();
    if (validationError != null) {
      state = state.copyWith(error: validationError);
      return;
    }

    state = state.copyWith(isLoading: true, error: null);
    try {
      await _service.updateSosSettings(userId, newSettings);
      state = state.copyWith(sosSettings: newSettings, isLoading: false);
      _syncToInMemoryServices(newSettings, state.fakeCallSettings);
      _cacheToPrefs(newSettings, state.fakeCallSettings);
      AppLogger.info('ProfileSettingsNotifier: SOS settings updated successfully');
    } catch (e) {
      AppLogger.error('ProfileSettingsNotifier: Failed to update SOS settings', e);
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> updateFakeCallSettings(FakeCallSettings newSettings) async {
    final userId = _ref.read(authStateProvider).user?.id;
    if (userId == null) return;

    final validationError = newSettings.validate();
    if (validationError != null) {
      state = state.copyWith(error: validationError);
      return;
    }

    state = state.copyWith(isLoading: true, error: null);
    try {
      await _service.updateFakeCallSettings(userId, newSettings);
      state = state.copyWith(fakeCallSettings: newSettings, isLoading: false);
      _syncToInMemoryServices(state.sosSettings, newSettings);
      _cacheToPrefs(state.sosSettings, newSettings);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> updateProfile({String? name, String? phone}) async {
    final userId = _ref.read(authStateProvider).user?.id;
    if (userId == null) return;

    state = state.copyWith(isLoading: true, error: null);
    try {
      await _service.updateProfile(userId, name: name, phone: phone);
      state = state.copyWith(
        name: name ?? state.name,
        phone: phone ?? state.phone,
        isLoading: false,
      );
      // Synchronize with authStateProvider so the UI updates
      await _ref.read(authStateProvider.notifier).updateProfile(name: name, phone: phone);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

final profileSettingsServiceProvider = Provider<ProfileSettingsService>((ref) {
  return ProfileSettingsService();
});

final profileSettingsProvider =
    StateNotifierProvider<ProfileSettingsNotifier, ProfileSettingsState>((ref) {
  final service = ref.watch(profileSettingsServiceProvider);
  return ProfileSettingsNotifier(ref, service);
});
