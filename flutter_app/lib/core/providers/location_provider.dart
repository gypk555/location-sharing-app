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

  LocationNotifier(this._locationService) : super(const LocationState()) {
    _checkPermission();
  }

  /// Safely update state only if the notifier is still mounted.
  void _safeSetState(LocationState newState) {
    if (mounted) {
      state = newState;
    }
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
    _safeSetState(state.copyWith(isLoading: true, error: null));
    try {
      final location = await _locationService.getCurrentLocation();
      if (!mounted) return;
      if (location != null) {
        _safeSetState(state.copyWith(currentLocation: location, isLoading: false));
      } else {
        _safeSetState(state.copyWith(
          isLoading: false,
          error: 'Could not get location',
        ));
      }
    } catch (e) {
      _safeSetState(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> startTracking() async {
    _safeSetState(state.copyWith(isLoading: true, error: null));

    final serviceEnabled = await _locationService.isServiceEnabled();
    AppLogger.info('startTracking: serviceEnabled=$serviceEnabled');
    if (!serviceEnabled) {
      _safeSetState(state.copyWith(
        isLoading: false,
        error: 'Location services are disabled. Turn on GPS in system settings.',
      ));
      return;
    }

    if (!state.hasPermission) {
      await requestPermission();
      AppLogger.info('startTracking: hasPermission=${state.hasPermission}');
      if (!mounted || !state.hasPermission) {
        _safeSetState(state.copyWith(
          isLoading: false,
          error: 'Location permission not granted. Enable it in system settings.',
        ));
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
    _safeSetState(state.copyWith(error: null));
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
    _locationSubscription?.cancel();
    super.dispose();
  }
}
