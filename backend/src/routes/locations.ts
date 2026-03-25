import { Elysia, t } from 'elysia';
import { getCollection, ObjectId } from '../utils/db';
import { Location, createLocation } from '../models/Location';
import { Friend } from '../models/Friend';
import { authMiddleware } from '../middleware/auth';

export const locationRoutes = new Elysia({ prefix: '/locations' })
  .use(authMiddleware)
  // Save location
  .post(
    '/',
    async ({ userId, body }) => {
      const locations = getCollection<Location>('locations');

      const location = createLocation(new ObjectId(userId), {
        latitude: body.latitude,
        longitude: body.longitude,
        accuracy: body.accuracy,
        altitude: body.altitude,
        heading: body.heading,
        speed: body.speed,
        source: body.source,
        batteryLevel: body.batteryLevel,
        isCharging: body.isCharging,
        networkType: body.networkType,
      });

      const result = await locations.insertOne(location);

      return {
        id: result.insertedId.toString(),
        timestamp: location.timestamp,
      };
    },
    {
      body: t.Object({
        latitude: t.Number({ minimum: -90, maximum: 90 }),
        longitude: t.Number({ minimum: -180, maximum: 180 }),
        accuracy: t.Number({ minimum: 0 }),
        altitude: t.Optional(t.Number()),
        heading: t.Optional(t.Number({ minimum: 0, maximum: 360 })),
        speed: t.Optional(t.Number({ minimum: 0 })),
        source: t.Optional(
          t.Union([t.Literal('gps'), t.Literal('network'), t.Literal('passive')])
        ),
        batteryLevel: t.Optional(t.Number({ minimum: 0, maximum: 100 })),
        isCharging: t.Optional(t.Boolean()),
        networkType: t.Optional(
          t.Union([t.Literal('wifi'), t.Literal('cellular'), t.Literal('none')])
        ),
      }),
      detail: {
        tags: ['Locations'],
        summary: 'Save location update',
      },
    }
  )
  // Get friends' current locations
  .get(
    '/friends',
    async ({ userId }) => {
      const friends = getCollection<Friend>('friends');
      const locations = getCollection<Location>('locations');

      const userObjectId = new ObjectId(userId);

      // Get accepted friends who allow location viewing
      const friendRecords = await friends
        .find({
          $or: [{ userId: userObjectId }, { friendId: userObjectId }],
          status: 'accepted',
          canViewLocation: true,
        })
        .toArray();

      const friendUserIds = friendRecords.map((f) =>
        f.userId.equals(userObjectId) ? f.friendId : f.userId
      );

      if (friendUserIds.length === 0) {
        return { locations: [] };
      }

      // Get latest location for each friend
      const pipeline = [
        {
          $match: {
            userId: { $in: friendUserIds },
          },
        },
        {
          $sort: { timestamp: -1 as const },
        },
        {
          $group: {
            _id: '$userId',
            latestLocation: { $first: '$$ROOT' },
          },
        },
      ];

      const latestLocations = await locations.aggregate(pipeline).toArray();

      return {
        locations: latestLocations.map((l) => ({
          userId: l._id.toString(),
          latitude: l.latestLocation.latitude,
          longitude: l.latestLocation.longitude,
          accuracy: l.latestLocation.accuracy,
          timestamp: l.latestLocation.timestamp,
        })),
      };
    },
    {
      detail: {
        tags: ['Locations'],
        summary: "Get friends' current locations",
      },
    }
  )
  // Get location history
  .get(
    '/history',
    async ({ userId, query, set }) => {
      const locations = getCollection<Location>('locations');
      const friends = getCollection<Friend>('friends');

      const userObjectId = new ObjectId(userId);
      let targetUserId = userObjectId;

      // If querying another user's history, check permissions
      if (query.userId && query.userId !== userId) {
        const targetId = new ObjectId(query.userId);

        const friendship = await friends.findOne({
          $or: [
            { userId: userObjectId, friendId: targetId },
            { userId: targetId, friendId: userObjectId },
          ],
          status: 'accepted',
          canViewHistory: true,
        });

        if (!friendship) {
          set.status = 403;
          return { error: 'Not authorized to view this history' };
        }

        targetUserId = targetId;
      }

      // Build query
      const filter: any = { userId: targetUserId };

      if (query.from) {
        filter.timestamp = { ...filter.timestamp, $gte: new Date(query.from) };
      }
      if (query.to) {
        filter.timestamp = { ...filter.timestamp, $lte: new Date(query.to) };
      }

      const limit = Math.min(query.limit || 100, 1000);
      const skip = query.offset || 0;

      const history = await locations
        .find(filter)
        .sort({ timestamp: -1 })
        .skip(skip)
        .limit(limit)
        .toArray();

      const total = await locations.countDocuments(filter);

      return {
        locations: history.map((l) => ({
          id: l._id!.toString(),
          latitude: l.latitude,
          longitude: l.longitude,
          accuracy: l.accuracy,
          altitude: l.altitude,
          heading: l.heading,
          speed: l.speed,
          timestamp: l.timestamp,
          sharedViaSms: l.sharedViaSms,
        })),
        total,
        limit,
        offset: skip,
      };
    },
    {
      query: t.Object({
        userId: t.Optional(t.String()),
        from: t.Optional(t.String()),
        to: t.Optional(t.String()),
        limit: t.Optional(t.Number({ minimum: 1, maximum: 1000 })),
        offset: t.Optional(t.Number({ minimum: 0 })),
      }),
      detail: {
        tags: ['Locations'],
        summary: 'Get location history',
      },
    }
  )
  // Delete location history
  .delete(
    '/history',
    async ({ userId, query }) => {
      const locations = getCollection<Location>('locations');

      const filter: any = { userId: new ObjectId(userId) };

      if (query.from) {
        filter.timestamp = { ...filter.timestamp, $gte: new Date(query.from) };
      }
      if (query.to) {
        filter.timestamp = { ...filter.timestamp, $lte: new Date(query.to) };
      }

      const result = await locations.deleteMany(filter);

      return {
        deleted: result.deletedCount,
      };
    },
    {
      query: t.Object({
        from: t.Optional(t.String()),
        to: t.Optional(t.String()),
      }),
      detail: {
        tags: ['Locations'],
        summary: 'Delete location history',
      },
    }
  );
