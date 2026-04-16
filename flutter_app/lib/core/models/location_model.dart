import 'package:hive/hive.dart';

part 'location_model.g.dart';

@HiveType(typeId: 2)
class LocationModel extends HiveObject {
  @HiveField(0)
  final double latitude;

  @HiveField(1)
  final double longitude;

  @HiveField(2)
  final double? accuracy;

  @HiveField(3)
  final double? altitude;

  @HiveField(4)
  final double? speed;

  @HiveField(5)
  final String? address;

  @HiveField(6)
  final DateTime timestamp;

  @HiveField(7)
  final bool isSynced; // For offline-first sync

  @HiveField(8)
  final double? heading;

  @HiveField(9)
  final int? batteryLevel;

  @HiveField(10)
  final bool? isCharging;

  LocationModel({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.altitude,
    this.speed,
    this.address,
    required this.timestamp,
    this.isSynced = false,
    this.heading,
    this.batteryLevel,
    this.isCharging,
  });

  factory LocationModel.fromJson(Map<String, dynamic> json) {
    return LocationModel(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      altitude: (json['altitude'] as num?)?.toDouble(),
      speed: (json['speed'] as num?)?.toDouble(),
      address: json['address'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
      isSynced: json['isSynced'] as bool? ?? false,
      heading: (json['heading'] as num?)?.toDouble(),
      batteryLevel: (json['batteryLevel'] as num?)?.toInt(),
      isCharging: json['isCharging'] as bool?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'altitude': altitude,
      'speed': speed,
      'address': address,
      'timestamp': timestamp.toIso8601String(),
      'isSynced': isSynced,
      'heading': heading,
      'batteryLevel': batteryLevel,
      'isCharging': isCharging,
    };
  }

  String get googleMapsUrl =>
      'https://maps.google.com/?q=$latitude,$longitude';

  String get coordinatesString => '$latitude, $longitude';

  LocationModel copyWith({
    double? latitude,
    double? longitude,
    double? accuracy,
    double? altitude,
    double? speed,
    String? address,
    DateTime? timestamp,
    bool? isSynced,
    double? heading,
    int? batteryLevel,
    bool? isCharging,
  }) {
    return LocationModel(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracy: accuracy ?? this.accuracy,
      altitude: altitude ?? this.altitude,
      speed: speed ?? this.speed,
      address: address ?? this.address,
      timestamp: timestamp ?? this.timestamp,
      isSynced: isSynced ?? this.isSynced,
      heading: heading ?? this.heading,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      isCharging: isCharging ?? this.isCharging,
    );
  }
}
