import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../services/location_service.dart';

/// Snapshot of the device's location access state for the Settings UI.
class LocationPermissionSnapshot {
  final LocationPermission permission;
  final bool serviceEnabled;

  const LocationPermissionSnapshot({
    required this.permission,
    required this.serviceEnabled,
  });

  bool get isGranted =>
      serviceEnabled &&
      (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse);

  bool get isDeniedForever => permission == LocationPermission.deniedForever;

  String get label {
    if (!serviceEnabled) return 'Location service off';
    switch (permission) {
      case LocationPermission.always:
        return 'Always allowed';
      case LocationPermission.whileInUse:
        return 'Allowed while using app';
      case LocationPermission.denied:
        return 'Denied';
      case LocationPermission.deniedForever:
        return 'Blocked';
      case LocationPermission.unableToDetermine:
        return 'Unknown';
    }
  }
}

/// Re-fetch with `ref.invalidate(locationPermissionProvider)` after the user
/// returns from OS settings.
final locationPermissionProvider =
    FutureProvider<LocationPermissionSnapshot>((ref) async {
  final permission = await Geolocator.checkPermission();
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  return LocationPermissionSnapshot(
    permission: permission,
    serviceEnabled: serviceEnabled,
  );
});

/// Helpers the Settings dialog calls on button taps.
class LocationPermissionActions {
  LocationPermissionActions._();

  static Future<bool> request() => LocationService().checkPermission();
  static Future<bool> openAppSettings() =>
      LocationService().openAppSettings();
  static Future<bool> openLocationSettings() =>
      LocationService().openLocationSettings();
}
