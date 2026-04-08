import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/sos_service.dart';
import '../models/contact_model.dart';
import '../../shared/constants/app_constants.dart';
import '../../shared/utils/logger.dart';

final sosServiceProvider = Provider<SosService>((ref) {
  final service = SosService();
  ref.onDispose(() => service.dispose());
  return service;
});

final sosStateProvider = StateNotifierProvider<SosNotifier, SosState>((ref) {
  final sosService = ref.watch(sosServiceProvider);
  return SosNotifier(sosService);
});

final sosStatusStreamProvider = StreamProvider<SosStatus>((ref) {
  final sosService = ref.watch(sosServiceProvider);
  return sosService.sosStatusStream;
});

final sosCountdownStreamProvider = StreamProvider<int>((ref) {
  final sosService = ref.watch(sosServiceProvider);
  return sosService.countdownStream;
});

// Alias for easier usage in screens
final sosProvider = sosStateProvider;

class SosState {
  final SosStatus status;
  final int countdown;
  final int countdownSeconds;
  final bool shakeEnabled;
  final int sosContactCount;
  final String? error;

  const SosState({
    this.status = SosStatus.idle,
    this.countdown = 5,
    this.countdownSeconds = 5,
    this.shakeEnabled = true,
    this.sosContactCount = 0,
    this.error,
  });

  SosState copyWith({
    SosStatus? status,
    int? countdown,
    int? countdownSeconds,
    bool? shakeEnabled,
    int? sosContactCount,
    String? error,
  }) {
    return SosState(
      status: status ?? this.status,
      countdown: countdown ?? this.countdown,
      countdownSeconds: countdownSeconds ?? this.countdownSeconds,
      shakeEnabled: shakeEnabled ?? this.shakeEnabled,
      sosContactCount: sosContactCount ?? this.sosContactCount,
      error: error,
    );
  }
}

class SosNotifier extends StateNotifier<SosState> {
  final SosService _sosService;
  StreamSubscription<SosStatus>? _statusSubscription;
  StreamSubscription<int>? _countdownSubscription;

  SosNotifier(this._sosService) : super(const SosState()) {
    _initializeListeners();
  }

  void _initializeListeners() {
    _statusSubscription = _sosService.sosStatusStream.listen((status) {
      state = state.copyWith(status: status);
    });

    _countdownSubscription = _sosService.countdownStream.listen((seconds) {
      state = state.copyWith(countdown: seconds, countdownSeconds: seconds);
    });

    _loadSosContactCount();
  }

  Future<void> _loadSosContactCount() async {
    try {
      // Check if box is already open to avoid reopening
      final box = Hive.isBoxOpen(AppConstants.contactsBoxName)
          ? Hive.box<ContactModel>(AppConstants.contactsBoxName)
          : await Hive.openBox<ContactModel>(AppConstants.contactsBoxName);
      final count = box.values.where((c) => c.isSosContact).length;

      // Check if notifier is still mounted before updating state
      // Prevents "setState after dispose" errors
      if (mounted) {
        state = state.copyWith(sosContactCount: count);
      }
    } catch (e) {
      // Log error for debugging instead of silently ignoring
      AppLogger.debug('Error loading SOS contact count: $e');
    }
  }

  void setShakeEnabled(bool enabled) {
    _sosService.setShakeEnabled(enabled);
    state = state.copyWith(shakeEnabled: enabled);
  }

  void setCountdownSeconds(int seconds) {
    _sosService.setCountdownSeconds(seconds);
    state = state.copyWith(countdownSeconds: seconds);
  }

  void startShakeDetection() {
    _sosService.startShakeDetection();
  }

  void stopShakeDetection() {
    _sosService.stopShakeDetection();
  }

  Future<void> triggerSosWithCountdown() async {
    await _sosService.triggerSosWithCountdown();
  }

  void cancelSos() {
    _sosService.cancelSos();
  }

  Future<void> triggerSosImmediately() async {
    await _sosService.triggerSosImmediately();
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _countdownSubscription?.cancel();
    super.dispose();
  }
}
