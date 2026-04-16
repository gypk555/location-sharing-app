import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/location_model.dart';
import '../../shared/constants/app_constants.dart';
import '../../shared/utils/logger.dart';

/// Adaptive tracking tiers. Each tier maps to different LocationSettings.
///
/// - [normal]: default while actively sharing; 15s interval, 25m filter
/// - [stationary]: user hasn't moved >25m in 2min; back off to 60s to save battery
/// - [emergency]: SOS active; 5s interval, no filter, best accuracy
enum TrackingTier { normal, stationary, emergency }

typedef LocationSink = void Function(LocationModel location);

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  StreamSubscription<Position>? _positionSubscription;
  StreamController<LocationModel>? _locationController;

  /// Observers notified on every position emission. Used by
  /// LiveLocationSharingService to write positions to Supabase without
  /// creating a second geolocator stream.
  final List<LocationSink> _externalSinks = [];

  /// Cached Hive box for performance
  Box<LocationModel>? _locationBox;

  /// Last geocoded address and timestamp for rate limiting
  String? _lastGeocodedAddress;
  DateTime? _lastGeocodingTime;
  double? _lastGeocodedLat;
  double? _lastGeocodedLng;

  /// Minimum interval between geocoding requests (5 minutes) - battery optimization
  static const _geocodingInterval = Duration(minutes: 5);

  /// Timeout for geocoding API calls
  static const _geocodingTimeout = Duration(seconds: 10);

  /// Distance threshold for reusing cached geocode (meters)
  static const _geocodingDistanceThreshold = 100.0;

  /// Current tracking tier. Changes via [setTier].
  TrackingTier _tier = TrackingTier.normal;
  TrackingTier get tier => _tier;

  /// Whether tracking is currently active (a subscription exists).
  bool get isTracking => _positionSubscription != null;

  /// Battery sampler (cached to avoid querying on every position).
  final Battery _battery = Battery();
  int? _cachedBatteryLevel;
  bool? _cachedIsCharging;
  DateTime? _lastBatterySampleAt;

  /// When true, this instance is running inside the background isolate.
  /// Geocoding is disabled in that case (platform channels unreliable on iOS
  /// background isolates, and battery life matters more there).
  bool _isBackgroundIsolate = false;
  void markAsBackgroundIsolate() => _isBackgroundIsolate = true;

  Stream<LocationModel> get locationStream {
    _locationController ??= StreamController<LocationModel>.broadcast();
    return _locationController!.stream;
  }

  LocationModel? _currentLocation;
  LocationModel? get currentLocation => _currentLocation;

  /// Register an external observer of position emissions.
  void addSink(LocationSink sink) {
    if (!_externalSinks.contains(sink)) _externalSinks.add(sink);
  }

  void removeSink(LocationSink sink) => _externalSinks.remove(sink);

  /// Get cached Hive box (performance: avoid reopening on every operation)
  Future<Box<LocationModel>> get _box async {
    if (_locationBox == null || !_locationBox!.isOpen) {
      _locationBox = await Hive.openBox<LocationModel>(AppConstants.locationBoxName);
    }
    return _locationBox!;
  }

  Future<bool> checkPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  Future<bool> isServiceEnabled() async {
    return Geolocator.isLocationServiceEnabled();
  }

  Future<bool> openLocationSettings() async {
    return Geolocator.openLocationSettings();
  }

  Future<bool> openAppSettings() async {
    return Geolocator.openAppSettings();
  }

  Future<LocationModel?> getCurrentLocation() async {
    try {
      final hasPermission = await checkPermission();
      if (!hasPermission) return null;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      final location = await _positionToLocationModel(position);
      _currentLocation = location;
      return location;
    } catch (e) {
      AppLogger.error('Error getting location', e);
      return null;
    }
  }

  /// Builds platform-specific LocationSettings for a given tier.
  LocationSettings _settingsForTier(TrackingTier tier) {
    late final LocationAccuracy accuracy;
    late final int distanceFilter;
    late final int intervalMs;

    switch (tier) {
      case TrackingTier.normal:
        accuracy = LocationAccuracy.high;
        distanceFilter = AppConstants.liveSharingNormalDistanceFilterMeters;
        intervalMs = AppConstants.locationUpdateIntervalSharingMs;
        break;
      case TrackingTier.stationary:
        accuracy = LocationAccuracy.medium;
        distanceFilter = AppConstants.liveSharingStationaryDistanceFilterMeters;
        intervalMs = AppConstants.locationUpdateIntervalNormalMs;
        break;
      case TrackingTier.emergency:
        accuracy = LocationAccuracy.bestForNavigation;
        distanceFilter = AppConstants.liveSharingEmergencyDistanceFilterMeters;
        intervalMs = AppConstants.locationUpdateIntervalEmergencyMs;
        break;
    }

    return AndroidSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilter,
      intervalDuration: Duration(milliseconds: intervalMs),
      foregroundNotificationConfig: null,
    );
  }

  Future<void> startTracking() async {
    final hasPermission = await checkPermission();
    if (!hasPermission) return;

    _positionSubscription?.cancel();

    // Ensure stream controller is initialized
    _locationController ??= StreamController<LocationModel>.broadcast();

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: _settingsForTier(_tier),
    ).listen(_onPosition);
  }

  /// Change the active tier. Cancels and resubscribes the position stream
  /// with new LocationSettings. Uses a 200ms overlap window so there is no
  /// dead gap during which no positions arrive.
  Future<void> setTier(TrackingTier newTier) async {
    if (newTier == _tier) return;
    _tier = newTier;
    if (_positionSubscription == null) return;

    final oldSub = _positionSubscription;
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: _settingsForTier(newTier),
    ).listen(_onPosition);

    // Brief overlap so the new stream has time to produce its first emission.
    await Future.delayed(const Duration(milliseconds: 200));
    await oldSub?.cancel();
  }

  Future<void> _onPosition(Position position) async {
    final location = await _positionToLocationModel(position);
    _currentLocation = location;

    if (_locationController != null && !_locationController!.isClosed) {
      _locationController!.add(location);
    }

    // Notify external observers (e.g. LiveLocationSharingService).
    // Defensive copy to tolerate concurrent modification during iteration.
    final sinks = List<LocationSink>.from(_externalSinks);
    for (final sink in sinks) {
      try {
        sink(location);
      } catch (e, stack) {
        AppLogger.error('Location sink threw', e, stack);
      }
    }

    if (!_isBackgroundIsolate) {
      await _saveLocationLocally(location);
    }
  }

  void stopTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  /// Check if we should skip geocoding based on rate limiting and distance
  bool _shouldSkipGeocoding(double lat, double lng) {
    if (_lastGeocodingTime == null) return false;

    // Rate limit: skip if less than 5 minutes since last geocoding
    final timeSinceLastGeocoding = DateTime.now().difference(_lastGeocodingTime!);
    if (timeSinceLastGeocoding < _geocodingInterval) {
      // Also check if we're still close to the last geocoded location
      if (_lastGeocodedLat != null && _lastGeocodedLng != null) {
        final distance = Geolocator.distanceBetween(
          _lastGeocodedLat!,
          _lastGeocodedLng!,
          lat,
          lng,
        );
        // If within threshold distance, reuse cached address
        if (distance < _geocodingDistanceThreshold) {
          return true;
        }
      }
    }
    return false;
  }

  /// Samples battery level + charging state, cached for [kBatterySampleInterval].
  /// Returns (level, isCharging). Null entries on failure.
  Future<(int?, bool?)> _sampleBattery() async {
    final now = DateTime.now();
    if (_lastBatterySampleAt != null &&
        now.difference(_lastBatterySampleAt!) < AppConstants.kBatterySampleInterval) {
      return (_cachedBatteryLevel, _cachedIsCharging);
    }
    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      _cachedBatteryLevel = level;
      _cachedIsCharging = state == BatteryState.charging || state == BatteryState.full;
      _lastBatterySampleAt = now;
    } catch (e) {
      AppLogger.debug('Battery sample failed: $e');
    }
    return (_cachedBatteryLevel, _cachedIsCharging);
  }

  Future<LocationModel> _positionToLocationModel(Position position) async {
    String? address;

    // Skip geocoding entirely in the background isolate (platform channels
    // unreliable on iOS background, and battery matters).
    if (_isBackgroundIsolate) {
      address = null;
    } else if (_shouldSkipGeocoding(position.latitude, position.longitude)) {
      // Reuse cached address
      address = _lastGeocodedAddress;
    } else {
      try {
        // Geocoding with timeout to prevent hanging
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        ).timeout(_geocodingTimeout);

        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          address =
              '${place.street}, ${place.locality}, ${place.administrativeArea}';

          // Cache the geocoding result
          _lastGeocodedAddress = address;
          _lastGeocodingTime = DateTime.now();
          _lastGeocodedLat = position.latitude;
          _lastGeocodedLng = position.longitude;
        }
      } on TimeoutException catch (_) {
        AppLogger.debug('Geocoding timed out, using cached address');
        address = _lastGeocodedAddress;
      } catch (e) {
        AppLogger.debug('Error getting address, using cached');
        address = _lastGeocodedAddress;
      }
    }

    final (batteryLevel, isCharging) = await _sampleBattery();

    return LocationModel(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      altitude: position.altitude,
      speed: position.speed,
      heading: position.heading,
      address: address,
      timestamp: DateTime.now(),
      batteryLevel: batteryLevel,
      isCharging: isCharging,
    );
  }

  Future<void> _saveLocationLocally(LocationModel location) async {
    try {
      // Use cached box for performance
      final box = await _box;
      await box.add(location);

      // Keep only last 1000 locations to save storage
      if (box.length > 1000) {
        await box.deleteAt(0);
      }
    } catch (e) {
      AppLogger.error('Error saving location', e);
    }
  }

  Future<List<LocationModel>> getUnsyncedLocations() async {
    try {
      final box = await _box;
      return box.values.where((loc) => !loc.isSynced).toList();
    } catch (e) {
      AppLogger.error('Error getting unsynced locations', e);
      return [];
    }
  }

  Future<void> markAsSynced(List<LocationModel> locations) async {
    try {
      final box = await _box;
      for (final location in locations) {
        final index = box.values.toList().indexOf(location);
        if (index != -1) {
          await box.putAt(
            index,
            location.copyWith(isSynced: true),
          );
        }
      }
    } catch (e) {
      AppLogger.error('Error marking as synced', e);
    }
  }

  String formatLocationForSms(LocationModel location) {
    final googleMapsLink = location.googleMapsUrl;
    if (location.address != null) {
      return '${location.address}\n$googleMapsLink';
    }
    return googleMapsLink;
  }

  /// Dispose resources - call when service is no longer needed
  /// Note: Since this is a singleton, this should only be called on app termination
  void dispose() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _locationController?.close();
    _locationController = null;
    _externalSinks.clear();
    // Clear cached box reference
    _locationBox = null;
    // Clear geocoding cache
    _lastGeocodedAddress = null;
    _lastGeocodingTime = null;
    _lastGeocodedLat = null;
    _lastGeocodedLng = null;
    _cachedBatteryLevel = null;
    _cachedIsCharging = null;
    _lastBatterySampleAt = null;
  }
}
