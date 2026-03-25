import { ObjectId } from 'mongodb';

export interface SmsSettings {
  enableAutoFallback: boolean;
  fallbackDelaySeconds: number;
  scheduledInterval: number | null; // Minutes, null = disabled
  scheduledContacts: ObjectId[];
  includeGoogleMapsLink: boolean;
  includeRawCoordinates: boolean;
  includeAccuracyInfo: boolean;
}

export interface User {
  _id?: ObjectId;

  // Firebase auth
  firebaseUid: string;

  // Authentication
  email?: string;
  phone: string;
  passwordHash?: string;

  // Social login IDs
  googleId?: string;
  appleId?: string;

  // Profile
  name: string;
  profilePicture?: string;

  // Location preferences
  locationSharingEnabled: boolean;
  shareAccuracy: 'high' | 'medium' | 'low';

  // SMS preferences
  smsSettings: SmsSettings;

  // Push notifications
  fcmToken?: string;
  apnsToken?: string;

  // Timestamps
  createdAt: Date;
  updatedAt: Date;
  lastActiveAt: Date;
}

export const defaultSmsSettings: SmsSettings = {
  enableAutoFallback: true,
  fallbackDelaySeconds: 30,
  scheduledInterval: null,
  scheduledContacts: [],
  includeGoogleMapsLink: true,
  includeRawCoordinates: true,
  includeAccuracyInfo: true,
};

export function createUser(data: Partial<User>): User {
  const now = new Date();
  return {
    firebaseUid: data.firebaseUid || '',
    phone: data.phone || '',
    email: data.email,
    name: data.name || 'User',
    googleId: data.googleId,
    appleId: data.appleId,
    profilePicture: data.profilePicture,
    locationSharingEnabled: false,
    shareAccuracy: 'high',
    smsSettings: { ...defaultSmsSettings, ...data.smsSettings },
    fcmToken: data.fcmToken,
    apnsToken: data.apnsToken,
    createdAt: now,
    updatedAt: now,
    lastActiveAt: now,
  };
}
