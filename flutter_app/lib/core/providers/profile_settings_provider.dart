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
      final sosSettings = SosSettings.fromJson(
          data['sos_settings'] as Map<String, dynamic>?);
      final fakeCallSettings = FakeCallSettings.fromJson(
          data['fake_call_settings'] as Map<String, dynamic>?);
      
      state = state.copyWith(
        sosSettings: sosSettings,
        fakeCallSettings: fakeCallSettings,
        name: data['name'] as String?,
        phone: data['phone'] as String?,
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
      sos = SosSettings.fromJson(
          jsonDecode(sosJson) as Map<String, dynamic>?);
    }

    FakeCallSettings fake = const FakeCallSettings();
    if (fakeJson != null) {
      fake = FakeCallSettings.fromJson(
          jsonDecode(fakeJson) as Map<String, dynamic>?);
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
      final response = await _service.updateSosSettings(userId, newSettings);
      // Use the actual DB response to update local state
      final savedSettings = SosSettings.fromJson(
          response['sos_settings'] as Map<String, dynamic>?);
      state = state.copyWith(sosSettings: savedSettings, isLoading: false);
      _syncToInMemoryServices(savedSettings, state.fakeCallSettings);
      _cacheToPrefs(savedSettings, state.fakeCallSettings);
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
      final response = await _service.updateFakeCallSettings(userId, newSettings);
      // Use the actual DB response to update local state
      final savedSettings = FakeCallSettings.fromJson(
          response['fake_call_settings'] as Map<String, dynamic>?);
      state = state.copyWith(fakeCallSettings: savedSettings, isLoading: false);
      _syncToInMemoryServices(state.sosSettings, savedSettings);
      _cacheToPrefs(state.sosSettings, savedSettings);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> updateProfile({String? name, String? phone}) async {
    final userId = _ref.read(authStateProvider).user?.id;
    if (userId == null) return;

    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _service.updateProfile(userId, name: name, phone: phone);
      // Use the actual DB response to update local state only.
      // Do NOT call setUserLocally here — it triggers authStateProvider to
      // change, which fires _AuthNotifier.notifyListeners(), which causes
      // GoRouter to refresh mid-save, unmounting ProfileEditScreen before
      // context.pop() can run (the if (!mounted) return guard fires early).
      // SettingsScreen already reads profileSettings.name ?? authUser.name,
      // so it shows the correct updated value from profileSettingsProvider.
      final savedName = response['name'] as String? ?? state.name;
      final savedPhone = response['phone'] as String? ?? state.phone;
      state = state.copyWith(
        name: savedName,
        phone: savedPhone,
        isLoading: false,
      );
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
