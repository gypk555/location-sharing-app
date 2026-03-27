import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/location_service.dart';
import '../models/location_model.dart';

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

  Future<void> _checkPermission() async {
    final hasPermission = await _locationService.checkPermission();
    state = state.copyWith(hasPermission: hasPermission);
  }

  Future<void> requestPermission() async {
    state = state.copyWith(isLoading: true);
    final hasPermission = await _locationService.checkPermission();
    state = state.copyWith(hasPermission: hasPermission, isLoading: false);
  }

  Future<void> getCurrentLocation() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final location = await _locationService.getCurrentLocation();
      if (location != null) {
        state = state.copyWith(currentLocation: location, isLoading: false);
      } else {
        state = state.copyWith(
          isLoading: false,
          error: 'Could not get location',
        );
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> startTracking() async {
    if (!state.hasPermission) {
      await requestPermission();
      if (!state.hasPermission) return;
    }

    await _locationService.startTracking();

    _locationSubscription?.cancel();
    _locationSubscription = _locationService.locationStream.listen((location) {
      state = state.copyWith(currentLocation: location);
    });

    state = state.copyWith(isTracking: true);
  }

  void stopTracking() {
    _locationService.stopTracking();
    _locationSubscription?.cancel();
    _locationSubscription = null;
    state = state.copyWith(isTracking: false);
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }
}
