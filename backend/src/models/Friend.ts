import { ObjectId } from 'mongodb';

export type FriendStatus = 'pending' | 'accepted' | 'blocked';

export interface Friend {
  _id?: ObjectId;
  userId: ObjectId; // User who initiated or owns the record
  friendId: ObjectId; // The other user
  status: FriendStatus;

  // Permissions
  canViewLocation: boolean;
  canViewHistory: boolean;
  canReceiveSmsLocation: boolean;

  // Metadata
  nickname?: string;
  isFavorite: boolean;

  // Timestamps
  requestedAt: Date;
  acceptedAt?: Date;
}

export function createFriendRequest(
  userId: ObjectId,
  friendId: ObjectId
): Friend {
  return {
    userId,
    friendId,
    status: 'pending',
    canViewLocation: true,
    canViewHistory: false,
    canReceiveSmsLocation: false,
    isFavorite: false,
    requestedAt: new Date(),
  };
}

export function acceptFriendRequest(friend: Friend): Friend {
  return {
    ...friend,
    status: 'accepted',
    acceptedAt: new Date(),
  };
}
