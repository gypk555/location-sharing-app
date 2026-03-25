import { ObjectId } from 'mongodb';

export type SmsMessageType = 'manual' | 'auto_fallback' | 'sos' | 'scheduled';
export type SmsStatus = 'pending' | 'sent' | 'delivered' | 'failed';

export interface SmsLog {
  _id?: ObjectId;
  userId: ObjectId; // Sender

  // Recipient
  recipientPhone: string;
  recipientUserId?: ObjectId; // If recipient is app user
  recipientName: string;

  // Location shared
  latitude: number;
  longitude: number;
  accuracy: number;

  // Message details
  messageType: SmsMessageType;
  messageContent: string;
  googleMapsLink?: string;

  // Status
  status: SmsStatus;
  errorMessage?: string;

  // Trigger context
  triggerReason?: string;
  offlineDuration?: number; // Seconds offline before auto-trigger

  // Timestamps
  createdAt: Date;
  sentAt?: Date;
  deliveredAt?: Date;
}

export function createSmsLog(
  userId: ObjectId,
  data: {
    recipientPhone: string;
    recipientName: string;
    recipientUserId?: ObjectId;
    latitude: number;
    longitude: number;
    accuracy: number;
    messageType: SmsMessageType;
    messageContent: string;
    googleMapsLink?: string;
    triggerReason?: string;
    offlineDuration?: number;
  }
): SmsLog {
  return {
    userId,
    recipientPhone: data.recipientPhone,
    recipientName: data.recipientName,
    recipientUserId: data.recipientUserId,
    latitude: data.latitude,
    longitude: data.longitude,
    accuracy: data.accuracy,
    messageType: data.messageType,
    messageContent: data.messageContent,
    googleMapsLink: data.googleMapsLink,
    status: 'pending',
    triggerReason: data.triggerReason,
    offlineDuration: data.offlineDuration,
    createdAt: new Date(),
  };
}
