import { Elysia, t } from 'elysia';
import { getCollection, ObjectId } from '../utils/db';
import { User } from '../models/User';
import { authMiddleware } from '../middleware/auth';

export const userRoutes = new Elysia({ prefix: '/users' })
  .use(authMiddleware)
  // Get current user profile
  .get(
    '/me',
    async ({ userId, set }) => {
      const users = getCollection<User>('users');
      const user = await users.findOne({ _id: new ObjectId(userId) });

      if (!user) {
        set.status = 404;
        return { error: 'User not found' };
      }

      return {
        id: user._id!.toString(),
        email: user.email,
        phone: user.phone,
        name: user.name,
        profilePicture: user.profilePicture,
        locationSharingEnabled: user.locationSharingEnabled,
        shareAccuracy: user.shareAccuracy,
        smsSettings: user.smsSettings,
        createdAt: user.createdAt,
      };
    },
    {
      detail: {
        tags: ['Users'],
        summary: 'Get current user profile',
      },
    }
  )
  // Update user profile
  .put(
    '/me',
    async ({ userId, body, set }) => {
      const users = getCollection<User>('users');

      const updateData: Partial<User> = {
        updatedAt: new Date(),
      };

      if (body.name !== undefined) updateData.name = body.name;
      if (body.profilePicture !== undefined)
        updateData.profilePicture = body.profilePicture;
      if (body.locationSharingEnabled !== undefined)
        updateData.locationSharingEnabled = body.locationSharingEnabled;
      if (body.shareAccuracy !== undefined)
        updateData.shareAccuracy = body.shareAccuracy;

      const result = await users.updateOne(
        { _id: new ObjectId(userId) },
        { $set: updateData }
      );

      if (result.matchedCount === 0) {
        set.status = 404;
        return { error: 'User not found' };
      }

      return { success: true };
    },
    {
      body: t.Object({
        name: t.Optional(t.String()),
        profilePicture: t.Optional(t.String()),
        locationSharingEnabled: t.Optional(t.Boolean()),
        shareAccuracy: t.Optional(
          t.Union([t.Literal('high'), t.Literal('medium'), t.Literal('low')])
        ),
      }),
      detail: {
        tags: ['Users'],
        summary: 'Update user profile',
      },
    }
  )
  // Update SMS settings
  .put(
    '/me/sms-settings',
    async ({ userId, body, set }) => {
      const users = getCollection<User>('users');

      const result = await users.updateOne(
        { _id: new ObjectId(userId) },
        {
          $set: {
            'smsSettings.enableAutoFallback': body.enableAutoFallback,
            'smsSettings.fallbackDelaySeconds': body.fallbackDelaySeconds,
            'smsSettings.scheduledInterval': body.scheduledInterval,
            'smsSettings.includeGoogleMapsLink': body.includeGoogleMapsLink,
            'smsSettings.includeRawCoordinates': body.includeRawCoordinates,
            'smsSettings.includeAccuracyInfo': body.includeAccuracyInfo,
            updatedAt: new Date(),
          },
        }
      );

      if (result.matchedCount === 0) {
        set.status = 404;
        return { error: 'User not found' };
      }

      return { success: true };
    },
    {
      body: t.Object({
        enableAutoFallback: t.Boolean(),
        fallbackDelaySeconds: t.Number({ minimum: 10, maximum: 300 }),
        scheduledInterval: t.Nullable(t.Number({ minimum: 15, maximum: 1440 })),
        includeGoogleMapsLink: t.Boolean(),
        includeRawCoordinates: t.Boolean(),
        includeAccuracyInfo: t.Boolean(),
      }),
      detail: {
        tags: ['Users'],
        summary: 'Update SMS settings',
      },
    }
  )
  // Search users
  .get(
    '/search',
    async ({ query }) => {
      const users = getCollection<User>('users');

      const searchQuery = query.q;
      if (!searchQuery || searchQuery.length < 3) {
        return { users: [] };
      }

      // Search by email or phone
      const results = await users
        .find({
          $or: [
            { email: { $regex: searchQuery, $options: 'i' } },
            { phone: { $regex: searchQuery } },
            { name: { $regex: searchQuery, $options: 'i' } },
          ],
        })
        .limit(20)
        .toArray();

      return {
        users: results.map((u) => ({
          id: u._id!.toString(),
          name: u.name,
          profilePicture: u.profilePicture,
          // Don't expose full phone/email for privacy
        })),
      };
    },
    {
      query: t.Object({
        q: t.String(),
      }),
      detail: {
        tags: ['Users'],
        summary: 'Search users by email, phone, or name',
      },
    }
  );
