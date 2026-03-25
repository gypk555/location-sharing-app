import { ObjectId } from 'mongodb';

export interface GeoJsonPoint {
  type: 'Point';
  coordinates: [number, number]; // [longitude, latitude]
}

export interface Location {
  _id?: ObjectId;
  userId: ObjectId;

  // Coordinates
  latitude: number;
  longitude: number;
  accuracy: number; // Meters
  altitude?: number;
  altitudeAccuracy?: number;
  heading?: number; // 0-360 degrees
  speed?: number; // m/s

  // GeoJSON for MongoDB geospatial queries
  location: GeoJsonPoint;

  // Metadata
  source: 'gps' | 'network' | 'passive';
  batteryLevel?: number; // 0-100
  isCharging?: boolean;
  networkType?: 'wifi' | 'cellular' | 'none';

  // SMS tracking
  sharedViaSms: boolean;
  smsRecipients?: string[];

  // Timestamp
  timestamp: Date;
}

export function createLocation(
  userId: ObjectId,
  data: {
    latitude: number;
    longitude: number;
    accuracy: number;
    altitude?: number;
    altitudeAccuracy?: number;
    heading?: number;
    speed?: number;
    source?: 'gps' | 'network' | 'passive';
    batteryLevel?: number;
    isCharging?: boolean;
    networkType?: 'wifi' | 'cellular' | 'none';
  }
): Location {
  return {
    userId,
    latitude: data.latitude,
    longitude: data.longitude,
    accuracy: data.accuracy,
    altitude: data.altitude,
    altitudeAccuracy: data.altitudeAccuracy,
    heading: data.heading,
    speed: data.speed,
    location: {
      type: 'Point',
      coordinates: [data.longitude, data.latitude],
    },
    source: data.source || 'gps',
    batteryLevel: data.batteryLevel,
    isCharging: data.isCharging,
    networkType: data.networkType,
    sharedViaSms: false,
    timestamp: new Date(),
  };
}
