import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';
import '../models/user_model.dart';
import '../../shared/utils/logger.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final authService = ref.watch(authServiceProvider);
  return AuthNotifier(authService);
});

class AuthState {
  final UserModel? user;
  final bool isLoading;
  final bool hasInitialized;
  final String? initError;
  final String? error;

  static const _unset = Object();

  const AuthState({
    this.user,
    this.isLoading = false,
    this.hasInitialized = false,
    this.initError,
    this.error,
  });

  bool get isAuthenticated => user != null;

  AuthState copyWith({
    UserModel? user,
    bool? isLoading,
    bool? hasInitialized,
    Object? initError = _unset,
    String? error,
  }) {
    return AuthState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      hasInitialized: hasInitialized ?? this.hasInitialized,
      initError: initError == _unset ? this.initError : initError as String?,
      error: error,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _authService;

  AuthNotifier(this._authService) : super(const AuthState(isLoading: true)) {
    _initialize();
  }

  /// Safely update state only if the notifier is still mounted.
  /// This prevents "setState after dispose" errors when async operations
  /// complete after the widget has been disposed.
  void _safeSetState(AuthState newState) {
    if (mounted) {
      state = newState;
    }
  }

  Future<void> _initialize() async {
    try {
      final sw = Stopwatch()..start();
      AppLogger.info('AuthNotifier._initialize start');
      final cachedUser = await _authService.loadCachedUserFast();
      _safeSetState(AuthState(
        user: cachedUser,
        isLoading: cachedUser == null,
        hasInitialized: cachedUser != null,
        initError: null,
      ));
      sw.stop();
      AppLogger.info(
        'AuthNotifier._initialize quick done in ${sw.elapsedMilliseconds}ms, '
        'user=${cachedUser != null}',
      );
      unawaited(_hydrateFromHive());
    } catch (e) {
      // Log full error for debugging (never expose to user)
      AppLogger.error('Auth initialization failed', e);

      // Show user-friendly message instead of raw error
      _safeSetState(AuthState(
        user: null,
        isLoading: false,
        hasInitialized: true,
        initError: 'Could not connect to server. Please check your internet connection.',
        error: 'Could not connect to server. Please check your internet connection.',
      ));
    }
  }

  Future<void> _hydrateFromHive() async {
    try {
      final sw = Stopwatch()..start();
      final hiveUser = await _authService.loadStoredUserFromHive();
      if (!mounted) return;
      if (hiveUser?.id != state.user?.id || !state.hasInitialized) {
        _safeSetState(AuthState(
          user: hiveUser,
          isLoading: false,
          hasInitialized: true,
          initError: state.initError,
          error: state.error,
        ));
      }
      sw.stop();
      AppLogger.info(
        'AuthNotifier._hydrateFromHive done in ${sw.elapsedMilliseconds}ms, '
        'user=${hiveUser != null}',
      );
    } catch (e) {
      AppLogger.error('Auth hydrate failed', e);
      // Ensure we don't get stuck on splash if Hive load fails
      if (mounted && !state.hasInitialized) {
        _safeSetState(AuthState(
          user: state.user,
          isLoading: false,
          hasInitialized: true,
          initError: state.initError,
          error: state.error,
        ));
      }
    }
  }

  Future<void> sendPhoneOtp(String phone) async {
    _safeSetState(state.copyWith(isLoading: true, error: null));
    try {
      await _authService.sendPhoneOtp(phone);
      _safeSetState(state.copyWith(isLoading: false));
    } catch (e) {
      _safeSetState(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> verifyPhoneOtp(String phone, String otp) async {
    _safeSetState(state.copyWith(isLoading: true, error: null));
    try {
      final user = await _authService.verifyPhoneOtp(phone, otp);
      _safeSetState(state.copyWith(user: user, isLoading: false));
    } catch (e) {
      _safeSetState(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> registerWithEmail(
      String email, String password, String name) async {
    _safeSetState(state.copyWith(isLoading: true, error: null));
    try {
      final user = await _authService.registerWithEmail(email, password, name);
      _safeSetState(state.copyWith(user: user, isLoading: false));
    } catch (e) {
      _safeSetState(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> loginWithEmail(String email, String password) async {
    _safeSetState(state.copyWith(isLoading: true, error: null));
    try {
      final user = await _authService.loginWithEmail(email, password);
      _safeSetState(state.copyWith(user: user, isLoading: false));
    } catch (e) {
      _safeSetState(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> signInWithGoogle() async {
    _safeSetState(state.copyWith(isLoading: true, error: null));
    try {
      final user = await _authService.signInWithGoogle();
      _safeSetState(state.copyWith(user: user, isLoading: false));
    } catch (e) {
      _safeSetState(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> signInWithApple() async {
    _safeSetState(state.copyWith(isLoading: true, error: null));
    try {
      final user = await _authService.signInWithApple();
      _safeSetState(state.copyWith(user: user, isLoading: false));
    } catch (e) {
      _safeSetState(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  /// Update the signed-in user's name and/or phone. Either argument may be
  /// null to leave that field unchanged. Throws nothing — errors land in
  /// `state.error` so the dialog can surface them inline.
  Future<bool> updateProfile({String? name, String? phone}) async {
    if (state.user == null) return false;
    _safeSetState(state.copyWith(isLoading: true, error: null));
    try {
      if (phone != null && phone.isNotEmpty) {
        await _authService.updatePhone(phone);
      }
      if (name != null && name.isNotEmpty) {
        await _authService.updateProfile(name: name);
      }
      _safeSetState(state.copyWith(
        user: _authService.currentUser,
        isLoading: false,
      ));
      return true;
    } catch (e) {
      _safeSetState(state.copyWith(isLoading: false, error: e.toString()));
      return false;
    }
  }

  Future<void> signOut() async {
    _safeSetState(state.copyWith(isLoading: true, error: null));
    try {
      await _authService.signOut();
      _safeSetState(const AuthState(isLoading: false, hasInitialized: true));
    } catch (e) {
      _safeSetState(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> retryInitialize() async {
    _safeSetState(const AuthState(isLoading: true, hasInitialized: false));
    await _initialize();
  }

  void clearError() {
    _safeSetState(state.copyWith(error: null));
  }
}
