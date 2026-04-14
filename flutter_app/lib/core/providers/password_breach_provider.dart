import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/password_breach_service.dart';

/// Key prefix for storing "Don't show again" preference (user-specific)
const _kDontShowBreachWarningKeyPrefix = 'dont_show_breach_warning_';

/// Provider for the password breach service.
///
/// Deliberately NOT autoDispose: the service holds a Dio HTTP client and is
/// used for async operations during login (`ref.read` + `await checkPassword`).
/// With autoDispose, the provider would be disposed the moment the synchronous
/// `ref.read` returns, closing the Dio client mid-request and causing every
/// breach check to fail with a network error. The service lives for the app
/// lifetime; `ref.onDispose` still fires on ProviderScope teardown (app exit).
final passwordBreachServiceProvider = Provider<PasswordBreachService>((ref) {
  final service = PasswordBreachService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// State for password breach check UI
enum PasswordBreachState {
  idle,
  checking,
  safe,
  breached,
  offline,
  error,
}

/// Extended state with breach count for display
class PasswordBreachCheckState {
  final PasswordBreachState state;
  final int breachCount;
  final String? errorMessage;

  const PasswordBreachCheckState({
    this.state = PasswordBreachState.idle,
    this.breachCount = 0,
    this.errorMessage,
  });

  bool get isBreached => state == PasswordBreachState.breached;
  bool get isSafe => state == PasswordBreachState.safe;
  bool get isChecking => state == PasswordBreachState.checking;
  bool get isIdle => state == PasswordBreachState.idle;
  bool get isOffline => state == PasswordBreachState.offline;
  bool get hasError => state == PasswordBreachState.error;

  PasswordBreachCheckState copyWith({
    PasswordBreachState? state,
    int? breachCount,
    String? errorMessage,
  }) {
    return PasswordBreachCheckState(
      state: state ?? this.state,
      breachCount: breachCount ?? this.breachCount,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  String toString() => 'PasswordBreachCheckState(state: $state, breachCount: $breachCount)';
}

/// Notifier for password breach check state
class PasswordBreachCheckNotifier extends StateNotifier<PasswordBreachCheckState> {
  PasswordBreachCheckNotifier() : super(const PasswordBreachCheckState());

  /// Safely update state only if the notifier is still mounted.
  void _safeSetState(PasswordBreachCheckState newState) {
    if (mounted) {
      state = newState;
    }
  }

  /// Reset to idle state
  void reset() => _safeSetState(const PasswordBreachCheckState());

  /// Set checking/loading state
  void setChecking() => _safeSetState(state.copyWith(state: PasswordBreachState.checking));

  /// Update state based on service result
  void setResult(PasswordBreachResult result) {
    if (!mounted) return;
    switch (result.status) {
      case BreachCheckStatus.safe:
        _safeSetState(state.copyWith(state: PasswordBreachState.safe));
        break;
      case BreachCheckStatus.breached:
        _safeSetState(state.copyWith(
          state: PasswordBreachState.breached,
          breachCount: result.breachCount,
        ));
        break;
      case BreachCheckStatus.offline:
        _safeSetState(state.copyWith(state: PasswordBreachState.offline));
        break;
      case BreachCheckStatus.timeout:
      case BreachCheckStatus.error:
        _safeSetState(state.copyWith(
          state: PasswordBreachState.error,
          errorMessage: result.errorMessage,
        ));
        break;
    }
  }
}

/// Provider for password breach check state (used by UI)
final passwordBreachCheckProvider =
    StateNotifierProvider<PasswordBreachCheckNotifier, PasswordBreachCheckState>((ref) {
  return PasswordBreachCheckNotifier();
});

/// Provider to track if we need to show breach warning after login on HomeScreen
/// This persists across navigation so the warning can be shown after redirect
final showBreachWarningProvider = StateProvider<bool>((ref) => false);

/// Provider to track if user chose "Don't show again" for breach warnings
/// Persists across app restarts using SharedPreferences (user-specific)
final dontShowBreachWarningProvider = StateNotifierProvider<DontShowBreachWarningNotifier, bool>((ref) {
  return DontShowBreachWarningNotifier();
});

/// Notifier that syncs "Don't show again" preference with SharedPreferences
/// Preference is stored per-user to handle multiple users on same device
class DontShowBreachWarningNotifier extends StateNotifier<bool> {
  String? _currentUserId;

  DontShowBreachWarningNotifier() : super(false);

  /// Safely update state only if the notifier is still mounted.
  void _safeSetState(bool newState) {
    if (mounted) {
      state = newState;
    }
  }

  /// Get the storage key for current user
  String get _storageKey => '$_kDontShowBreachWarningKeyPrefix${_currentUserId ?? 'anonymous'}';

  /// Load preference for a specific user (call this after login)
  Future<void> loadForUser(String userId) async {
    _currentUserId = userId;
    final prefs = await SharedPreferences.getInstance();
    _safeSetState(prefs.getBool(_storageKey) ?? false);
  }

  /// Set preference and save to SharedPreferences
  Future<void> setDontShowAgain(bool value) async {
    if (_currentUserId == null) return;
    _safeSetState(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_storageKey, value);
  }

  /// Reset preference for current user
  Future<void> reset() async {
    _safeSetState(false);
    if (_currentUserId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  /// Clear state on logout (don't delete preference, just reset in-memory state)
  void clearOnLogout() {
    _currentUserId = null;
    _safeSetState(false);
  }
}
