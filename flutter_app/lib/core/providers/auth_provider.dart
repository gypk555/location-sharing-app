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
  final String? error;

  const AuthState({
    this.user,
    this.isLoading = false,
    this.error,
  });

  bool get isAuthenticated => user != null;

  AuthState copyWith({
    UserModel? user,
    bool? isLoading,
    String? error,
  }) {
    return AuthState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
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
      await _authService.initialize();
      _safeSetState(AuthState(user: _authService.currentUser, isLoading: false));
    } catch (e) {
      // Log full error for debugging (never expose to user)
      AppLogger.error('Auth initialization failed', e);

      // Show user-friendly message instead of raw error
      _safeSetState(AuthState(
        user: null,
        isLoading: false,
        error: 'Could not connect to server. Please check your internet connection.',
      ));
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

  Future<void> signOut() async {
    _safeSetState(state.copyWith(isLoading: true, error: null));
    try {
      await _authService.signOut();
      _safeSetState(const AuthState(isLoading: false));
    } catch (e) {
      _safeSetState(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  void clearError() {
    _safeSetState(state.copyWith(error: null));
  }
}
