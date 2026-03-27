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

  LocationModel({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.altitude,
    this.speed,
    this.address,
    required this.timestamp,
    this.isSynced = false,
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
    );
  }
}
