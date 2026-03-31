import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/password_breach_service.dart';

/// Provider for the password breach service (auto-disposed to clean up Dio client)
final passwordBreachServiceProvider = Provider.autoDispose<PasswordBreachService>((ref) {
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

  /// Reset to idle state
  void reset() => state = const PasswordBreachCheckState();

  /// Set checking/loading state
  void setChecking() => state = state.copyWith(state: PasswordBreachState.checking);

  /// Update state based on service result
  void setResult(PasswordBreachResult result) {
    switch (result.status) {
      case BreachCheckStatus.safe:
        state = state.copyWith(state: PasswordBreachState.safe);
        break;
      case BreachCheckStatus.breached:
        state = state.copyWith(
          state: PasswordBreachState.breached,
          breachCount: result.breachCount,
        );
        break;
      case BreachCheckStatus.offline:
        state = state.copyWith(state: PasswordBreachState.offline);
        break;
      case BreachCheckStatus.timeout:
      case BreachCheckStatus.error:
        state = state.copyWith(
          state: PasswordBreachState.error,
          errorMessage: result.errorMessage,
        );
        break;
    }
  }
}

/// Provider for password breach check state (used by UI)
final passwordBreachCheckProvider =
    StateNotifierProvider<PasswordBreachCheckNotifier, PasswordBreachCheckState>((ref) {
  return PasswordBreachCheckNotifier();
});
