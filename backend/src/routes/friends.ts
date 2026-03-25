import { Elysia, t } from 'elysia';
import { getCollection, ObjectId } from '../utils/db';
import { Friend, createFriendRequest, acceptFriendRequest } from '../models/Friend';
import { User } from '../models/User';
import { authMiddleware } from '../middleware/auth';

export const friendRoutes = new Elysia({ prefix: '/friends' })
  .use(authMiddleware)
  // List friends
  .get(
    '/',
    async ({ userId, query }) => {
      const friends = getCollection<Friend>('friends');
      const users = getCollection<User>('users');

      const status = query.status || 'accepted';
      const userObjectId = new ObjectId(userId);

      // Get friends where user is either the requester or the recipient
      const friendRecords = await friends
        .find({
          $or: [{ userId: userObjectId }, { friendId: userObjectId }],
          status: status,
        })
        .toArray();

      // Get friend user details
      const friendUserIds = friendRecords.map((f) =>
        f.userId.equals(userObjectId) ? f.friendId : f.userId
      );

      const friendUsers = await users
        .find({ _id: { $in: friendUserIds } })
        .toArray();

      const userMap = new Map(friendUsers.map((u) => [u._id!.toString(), u]));

      return {
        friends: friendRecords.map((f) => {
          const friendUserId = f.userId.equals(userObjectId)
            ? f.friendId
            : f.userId;
          const friendUser = userMap.get(friendUserId.toString());

          return {
            id: f._id!.toString(),
            friendId: friendUserId.toString(),
            name: friendUser?.name || 'Unknown',
            profilePicture: friendUser?.profilePicture,
            status: f.status,
            canViewLocation: f.canViewLocation,
            canViewHistory: f.canViewHistory,
            canReceiveSmsLocation: f.canReceiveSmsLocation,
            nickname: f.nickname,
            isFavorite: f.isFavorite,
            requestedAt: f.requestedAt,
            acceptedAt: f.acceptedAt,
            // Include if friend is sharing location
            isSharingLocation: friendUser?.locationSharingEnabled || false,
          };
        }),
      };
    },
    {
      query: t.Object({
        status: t.Optional(
          t.Union([
            t.Literal('pending'),
            t.Literal('accepted'),
            t.Literal('blocked'),
          ])
        ),
      }),
      detail: {
        tags: ['Friends'],
        summary: 'List friends',
      },
    }
  )
  // Send friend request
  .post(
    '/request',
    async ({ userId, body, set }) => {
      const friends = getCollection<Friend>('friends');
      const users = getCollection<User>('users');

      const userObjectId = new ObjectId(userId);
      const friendObjectId = new ObjectId(body.friendId);

      // Check if friend user exists
      const friendUser = await users.findOne({ _id: friendObjectId });
      if (!friendUser) {
        set.status = 404;
        return { error: 'User not found' };
      }

      // Check if already friends or request exists
      const existing = await friends.findOne({
        $or: [
          { userId: userObjectId, friendId: friendObjectId },
          { userId: friendObjectId, friendId: userObjectId },
        ],
      });

      if (existing) {
        if (existing.status === 'accepted') {
          set.status = 400;
          return { error: 'Already friends' };
        }
        if (existing.status === 'pending') {
          set.status = 400;
          return { error: 'Friend request already pending' };
        }
        if (existing.status === 'blocked') {
          set.status = 400;
          return { error: 'Cannot send request to this user' };
        }
      }

      // Create friend request
      const friendRequest = createFriendRequest(userObjectId, friendObjectId);
      const result = await friends.insertOne(friendRequest);

      return {
        id: result.insertedId.toString(),
        status: 'pending',
        message: 'Friend request sent',
      };
    },
    {
      body: t.Object({
        friendId: t.String(),
      }),
      detail: {
        tags: ['Friends'],
        summary: 'Send friend request',
      },
    }
  )
  // Accept friend request
  .post(
    '/:id/accept',
    async ({ userId, params, set }) => {
      const friends = getCollection<Friend>('friends');

      const userObjectId = new ObjectId(userId);
      const requestId = new ObjectId(params.id);

      // Find the pending request where this user is the recipient
      const request = await friends.findOne({
        _id: requestId,
        friendId: userObjectId,
        status: 'pending',
      });

      if (!request) {
        set.status = 404;
        return { error: 'Friend request not found' };
      }

      // Accept the request
      await friends.updateOne(
        { _id: requestId },
        {
          $set: {
            status: 'accepted',
            acceptedAt: new Date(),
          },
        }
      );

      // Create reverse friendship record
      const reverseFriend: Friend = {
        userId: userObjectId,
        friendId: request.userId,
        status: 'accepted',
        canViewLocation: true,
        canViewHistory: false,
        canReceiveSmsLocation: false,
        isFavorite: false,
        requestedAt: request.requestedAt,
        acceptedAt: new Date(),
      };

      await friends.insertOne(reverseFriend);

      return { success: true, message: 'Friend request accepted' };
    },
    {
      params: t.Object({
        id: t.String(),
      }),
      detail: {
        tags: ['Friends'],
        summary: 'Accept friend request',
      },
    }
  )
  // Remove friend
  .delete(
    '/:id',
    async ({ userId, params, set }) => {
      const friends = getCollection<Friend>('friends');

      const userObjectId = new ObjectId(userId);
      const friendId = new ObjectId(params.id);

      // Remove both direction friendship records
      await friends.deleteMany({
        $or: [
          { userId: userObjectId, friendId: friendId },
          { userId: friendId, friendId: userObjectId },
        ],
      });

      return { success: true, message: 'Friend removed' };
    },
    {
      params: t.Object({
        id: t.String(),
      }),
      detail: {
        tags: ['Friends'],
        summary: 'Remove friend',
      },
    }
  )
  // Update friend permissions
  .put(
    '/:id/permissions',
    async ({ userId, params, body, set }) => {
      const friends = getCollection<Friend>('friends');

      const userObjectId = new ObjectId(userId);
      const friendId = new ObjectId(params.id);

      const result = await friends.updateOne(
        {
          $or: [
            { userId: userObjectId, friendId: friendId },
            { userId: friendId, friendId: userObjectId },
          ],
          status: 'accepted',
        },
        {
          $set: {
            canViewLocation: body.canViewLocation,
            canViewHistory: body.canViewHistory,
            canReceiveSmsLocation: body.canReceiveSmsLocation,
          },
        }
      );

      if (result.matchedCount === 0) {
        set.status = 404;
        return { error: 'Friend not found' };
      }

      return { success: true };
    },
    {
      params: t.Object({
        id: t.String(),
      }),
      body: t.Object({
        canViewLocation: t.Boolean(),
        canViewHistory: t.Boolean(),
        canReceiveSmsLocation: t.Boolean(),
      }),
      detail: {
        tags: ['Friends'],
        summary: 'Update friend permissions',
      },
    }
  );
