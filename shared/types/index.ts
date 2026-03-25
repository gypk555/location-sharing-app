// Shared types between mobile and backend

export interface LocationData {
  latitude: number;
  longitude: number;
  accuracy: number;
  altitude?: number;
  altitudeAccuracy?: number;
  heading?: number;
  speed?: number;
  timestamp: Date;
}

export interface User {
  id: string;
  email?: string;
  phone: string;
  name: string;
  profilePicture?: string;
  locationSharingEnabled: boolean;
  shareAccuracy: 'high' | 'medium' | 'low';
  smsSettings: SmsSettings;
}

export interface SmsSettings {
  enableAutoFallback: boolean;
  fallbackDelaySeconds: number;
  scheduledInterval: number | null;
  includeGoogleMapsLink: boolean;
  includeRawCoordinates: boolean;
  includeAccuracyInfo: boolean;
}

export interface Friend {
  id: string;
  friendId: string;
  name: string;
  profilePicture?: string;
  status: 'pending' | 'accepted' | 'blocked';
  canViewLocation: boolean;
  canViewHistory: boolean;
  canReceiveSmsLocation: boolean;
  isSharingLocation: boolean;
}

export interface EmergencyContact {
  id: string;
  name: string;
  phone: string;
  email?: string;
  relationship: 'family' | 'friend' | 'partner' | 'coworker' | 'other';
  enabledForSos: boolean;
  customMessage?: string;
}

export type SmsMessageType = 'manual' | 'auto_fallback' | 'sos' | 'scheduled';

export interface SmsLog {
  id: string;
  recipientPhone: string;
  recipientName: string;
  latitude: number;
  longitude: number;
  accuracy: number;
  messageType: SmsMessageType;
  status: 'pending' | 'sent' | 'delivered' | 'failed';
  googleMapsLink?: string;
  createdAt: Date;
  sentAt?: Date;
}

// WebSocket message types
export type WebSocketMessageType =
  | 'authenticate'
  | 'authenticated'
  | 'location:update'
  | 'location:receive'
  | 'location:start-sharing'
  | 'location:stop-sharing'
  | 'location:sharing-started'
  | 'location:sharing-stopped'
  | 'location:ack'
  | 'friend:online'
  | 'friend:offline'
  | 'ping'
  | 'pong'
  | 'error';

export interface WebSocketMessage {
  type: WebSocketMessageType;
  payload?: any;
}
