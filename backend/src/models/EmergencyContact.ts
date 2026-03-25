import { ObjectId } from 'mongodb';

export type Relationship = 'family' | 'friend' | 'partner' | 'coworker' | 'other';

export interface EmergencyContact {
  _id?: ObjectId;
  userId: ObjectId; // Owner

  // Contact info
  name: string;
  phone: string;
  email?: string;

  // Relationship
  relationship: Relationship;

  // SOS settings
  enabledForSos: boolean;
  customMessage?: string;

  // Timestamps
  createdAt: Date;
  updatedAt: Date;
}

export function createEmergencyContact(
  userId: ObjectId,
  data: {
    name: string;
    phone: string;
    email?: string;
    relationship?: Relationship;
    customMessage?: string;
  }
): EmergencyContact {
  const now = new Date();
  return {
    userId,
    name: data.name,
    phone: data.phone,
    email: data.email,
    relationship: data.relationship || 'other',
    enabledForSos: true,
    customMessage: data.customMessage,
    createdAt: now,
    updatedAt: now,
  };
}
