import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/location_service.dart';
import '../models/location_model.dart';
import '../../shared/utils/logger.dart';

final locationServiceProvider = Provider<LocationService>((ref) {
  final service = LocationService();
  ref.onDispose(() => service.dispose());
  return service;
});

final locationStateProvider =
    StateNotifierProvider<LocationNotifier, LocationState>((ref) {
  final locationService = ref.watch(locationServiceProvider);
  return LocationNotifier(locationService);
});

// Alias for easier usage in screens
final locationProvider = locationStateProvider;

final locationStreamProvider = StreamProvider<LocationModel>((ref) {
  final locationService = ref.watch(locationServiceProvider);
  return locationService.locationStream;
});

class LocationState {
  final LocationModel? currentLocation;
  final bool isTracking;
  final bool hasPermission;
  final bool isLoading;
  final String? error;

  const LocationState({
    this.currentLocation,
    this.isTracking = false,
    this.hasPermission = false,
    this.isLoading = false,
    this.error,
  });

  LocationState copyWith({
    LocationModel? currentLocation,
    bool? isTracking,
    bool? hasPermission,
    bool? isLoading,
    String? error,
  }) {
    return LocationState(
      currentLocation: currentLocation ?? this.currentLocation,
      isTracking: isTracking ?? this.isTracking,
      hasPermission: hasPermission ?? this.hasPermission,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class LocationNotifier extends StateNotifier<LocationState> {
  final LocationService _locationService;
  StreamSubscription<LocationModel>? _locationSubscription;

  // Transient error auto-dismiss: location errors are one-shot notifications
  // (e.g. "GPS disabled", "permission denied"). They should appear briefly
  // and then disappear on their own so stale banners don't linger on the
  // home screen across tab changes, app resumes, or after the user fixes
  // the problem in system settings.
  Timer? _errorClearTimer;
  static const Duration _errorDisplayDuration = Duration(seconds: 5);

  LocationNotifier(this._locationService) : super(const LocationState()) {
    _checkPermission();
  }

  /// Safely update state only if the notifier is still mounted.
  void _safeSetState(LocationState newState) {
    if (mounted) {
      state = newState;
    }
  }

  /// Set a transient error that auto-clears after [_errorDisplayDuration].
  /// Replaces any previously-scheduled clear.
  void _setTransientError(String error) {
    _errorClearTimer?.cancel();
    _safeSetState(state.copyWith(isLoading: false, error: error));
    _errorClearTimer = Timer(_errorDisplayDuration, () {
      if (!mounted) return;
      // Only clear if the error hasn't already been replaced by a new one.
      if (state.error == error) {
        _safeSetState(state.copyWith(error: null));
      }
    });
  }

  Future<void> _checkPermission() async {
    final hasPermission = await _locationService.checkPermission();
    _safeSetState(state.copyWith(hasPermission: hasPermission));
  }

  Future<void> requestPermission() async {
    _safeSetState(state.copyWith(isLoading: true));
    final hasPermission = await _locationService.checkPermission();
    _safeSetState(state.copyWith(hasPermission: hasPermission, isLoading: false));
  }

  Future<void> getCurrentLocation() async {
    _errorClearTimer?.cancel();
    _safeSetState(state.copyWith(isLoading: true, error: null));
    try {
      final location = await _locationService.getCurrentLocation();
      if (!mounted) return;
      if (location != null) {
        _safeSetState(state.copyWith(currentLocation: location, isLoading: false));
      } else {
        _setTransientError('Could not get location');
      }
    } catch (e) {
      _setTransientError(e.toString());
    }
  }

  Future<void> startTracking() async {
    _errorClearTimer?.cancel();
    _safeSetState(state.copyWith(isLoading: true, error: null));

    final serviceEnabled = await _locationService.isServiceEnabled();
    AppLogger.info('startTracking: serviceEnabled=$serviceEnabled');
    if (!serviceEnabled) {
      _setTransientError(
        'Location services are disabled. Turn on GPS in system settings.',
      );
      return;
    }

    if (!state.hasPermission) {
      await requestPermission();
      AppLogger.info('startTracking: hasPermission=${state.hasPermission}');
      if (!mounted || !state.hasPermission) {
        _setTransientError(
          'Location permission not granted. Enable it in system settings.',
        );
        return;
      }
    }

    await _locationService.startTracking();
    if (!mounted) return;

    _locationSubscription?.cancel();
    _locationSubscription = _locationService.locationStream.listen((location) {
      _safeSetState(state.copyWith(currentLocation: location));
    });

    _safeSetState(state.copyWith(isTracking: true, isLoading: false));
  }

  void clearError() {
    _errorClearTimer?.cancel();
    _safeSetState(state.copyWith(error: null));
  }

  /// Re-check permission/service state and clear the error ONLY if the
  /// condition that caused it has been resolved. Called when HomeScreen
  /// (re)mounts and when the app resumes from the background, so stale
  /// "services disabled" / "permission denied" banners disappear after
  /// the user fixes the setting in system preferences.
  Future<void> refreshErrorState() async {
    final currentError = state.error;
    if (currentError == null) return;

    final lower = currentError.toLowerCase();
    if (lower.contains('services')) {
      final enabled = await _locationService.isServiceEnabled();
      if (!mounted) return;
      if (enabled) {
        _safeSetState(state.copyWith(error: null));
      }
    } else if (lower.contains('permission')) {
      final hasPermission = await _locationService.checkPermission();
      if (!mounted) return;
      if (hasPermission) {
        _safeSetState(state.copyWith(hasPermission: true, error: null));
      }
    }
  }

  Future<void> openLocationSettings() async {
    await _locationService.openLocationSettings();
  }

  Future<void> openAppSettings() async {
    await _locationService.openAppSettings();
  }

  void stopTracking() {
    _locationService.stopTracking();
    _locationSubscription?.cancel();
    _locationSubscription = null;
    _safeSetState(state.copyWith(isTracking: false));
  }

  @override
  void dispose() {
    _errorClearTimer?.cancel();
    _locationSubscription?.cancel();
    super.dispose();
  }
}
