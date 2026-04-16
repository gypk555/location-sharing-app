// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'location_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class LocationModelAdapter extends TypeAdapter<LocationModel> {
  @override
  final int typeId = 2;

  @override
  LocationModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LocationModel(
      latitude: fields[0] as double,
      longitude: fields[1] as double,
      accuracy: fields[2] as double?,
      altitude: fields[3] as double?,
      speed: fields[4] as double?,
      address: fields[5] as String?,
      timestamp: fields[6] as DateTime,
      isSynced: fields[7] as bool,
      heading: fields[8] as double?,
      batteryLevel: fields[9] as int?,
      isCharging: fields[10] as bool?,
    );
  }

  @override
  void write(BinaryWriter writer, LocationModel obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.latitude)
      ..writeByte(1)
      ..write(obj.longitude)
      ..writeByte(2)
      ..write(obj.accuracy)
      ..writeByte(3)
      ..write(obj.altitude)
      ..writeByte(4)
      ..write(obj.speed)
      ..writeByte(5)
      ..write(obj.address)
      ..writeByte(6)
      ..write(obj.timestamp)
      ..writeByte(7)
      ..write(obj.isSynced)
      ..writeByte(8)
      ..write(obj.heading)
      ..writeByte(9)
      ..write(obj.batteryLevel)
      ..writeByte(10)
      ..write(obj.isCharging);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocationModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
