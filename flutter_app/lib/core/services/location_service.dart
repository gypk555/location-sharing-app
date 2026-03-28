import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/location_model.dart';
import '../../shared/constants/app_constants.dart';
import '../../shared/utils/logger.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  StreamSubscription<Position>? _positionSubscription;
  StreamController<LocationModel>? _locationController;

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

  Stream<LocationModel> get locationStream {
    _locationController ??= StreamController<LocationModel>.broadcast();
    return _locationController!.stream;
  }

  LocationModel? _currentLocation;
  LocationModel? get currentLocation => _currentLocation;

  /// Get cached Hive box (performance: avoid reopening on every operation)
  Future<Box<LocationModel>> get _box async {
    if (_locationBox == null || !_locationBox!.isOpen) {
      _locationBox = await Hive.openBox<LocationModel>(AppConstants.locationBoxName);
    }
    return _locationBox!;
  }

  Future<bool> checkPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

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

  Future<void> startTracking() async {
    final hasPermission = await checkPermission();
    if (!hasPermission) return;

    _positionSubscription?.cancel();

    // Ensure stream controller is initialized
    _locationController ??= StreamController<LocationModel>.broadcast();

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: AppConstants.locationDistanceFilterMeters,
    );

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) async {
      final location = await _positionToLocationModel(position);
      _currentLocation = location;
      // Check if controller is still open before adding
      if (_locationController != null && !_locationController!.isClosed) {
        _locationController!.add(location);
      }
      await _saveLocationLocally(location);
    });
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

  Future<LocationModel> _positionToLocationModel(Position position) async {
    String? address;

    // Rate-limited geocoding to save battery (only every 5 minutes or when moved significantly)
    if (_shouldSkipGeocoding(position.latitude, position.longitude)) {
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

    return LocationModel(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      altitude: position.altitude,
      speed: position.speed,
      address: address,
      timestamp: DateTime.now(),
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
    // Clear cached box reference
    _locationBox = null;
    // Clear geocoding cache
    _lastGeocodedAddress = null;
    _lastGeocodingTime = null;
    _lastGeocodedLat = null;
    _lastGeocodedLng = null;
  }
}
