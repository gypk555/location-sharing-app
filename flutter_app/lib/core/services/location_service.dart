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
  final _locationController = StreamController<LocationModel>.broadcast();

  Stream<LocationModel> get locationStream => _locationController.stream;
  LocationModel? _currentLocation;
  LocationModel? get currentLocation => _currentLocation;

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

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: AppConstants.locationDistanceFilterMeters,
    );

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) async {
      final location = await _positionToLocationModel(position);
      _currentLocation = location;
      _locationController.add(location);
      await _saveLocationLocally(location);
    });
  }

  void stopTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  Future<LocationModel> _positionToLocationModel(Position position) async {
    String? address;
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        address =
            '${place.street}, ${place.locality}, ${place.administrativeArea}';
      }
    } catch (e) {
      AppLogger.debug('Error getting address: $e');
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
      final box =
          await Hive.openBox<LocationModel>(AppConstants.locationBoxName);
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
      final box =
          await Hive.openBox<LocationModel>(AppConstants.locationBoxName);
      return box.values.where((loc) => !loc.isSynced).toList();
    } catch (e) {
      AppLogger.error('Error getting unsynced locations', e);
      return [];
    }
  }

  Future<void> markAsSynced(List<LocationModel> locations) async {
    try {
      final box =
          await Hive.openBox<LocationModel>(AppConstants.locationBoxName);
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

  void dispose() {
    _positionSubscription?.cancel();
    _locationController.close();
  }
}
