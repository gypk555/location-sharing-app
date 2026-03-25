import { Elysia, t } from 'elysia';
import { getCollection, ObjectId } from '../utils/db';
import { SmsLog, createSmsLog } from '../models/SmsLog';
import { authMiddleware } from '../middleware/auth';

export const smsRoutes = new Elysia({ prefix: '/sms' })
  .use(authMiddleware)
  // Log SMS send
  .post(
    '/log',
    async ({ userId, body }) => {
      const smsLogs = getCollection<SmsLog>('smsLogs');

      const log = createSmsLog(new ObjectId(userId), {
        recipientPhone: body.recipientPhone,
        recipientName: body.recipientName,
        recipientUserId: body.recipientUserId
          ? new ObjectId(body.recipientUserId)
          : undefined,
        latitude: body.latitude,
        longitude: body.longitude,
        accuracy: body.accuracy,
        messageType: body.messageType,
        messageContent: body.messageContent,
        googleMapsLink: body.googleMapsLink,
        triggerReason: body.triggerReason,
        offlineDuration: body.offlineDuration,
      });

      // Mark as sent since client already sent it
      log.status = 'sent';
      log.sentAt = new Date();

      const result = await smsLogs.insertOne(log);

      return {
        id: result.insertedId.toString(),
        logged: true,
      };
    },
    {
      body: t.Object({
        recipientPhone: t.String(),
        recipientName: t.String(),
        recipientUserId: t.Optional(t.String()),
        latitude: t.Number({ minimum: -90, maximum: 90 }),
        longitude: t.Number({ minimum: -180, maximum: 180 }),
        accuracy: t.Number({ minimum: 0 }),
        messageType: t.Union([
          t.Literal('manual'),
          t.Literal('auto_fallback'),
          t.Literal('sos'),
          t.Literal('scheduled'),
        ]),
        messageContent: t.String(),
        googleMapsLink: t.Optional(t.String()),
        triggerReason: t.Optional(t.String()),
        offlineDuration: t.Optional(t.Number()),
      }),
      detail: {
        tags: ['SMS'],
        summary: 'Log an SMS send',
      },
    }
  )
  // Get SMS logs
  .get(
    '/logs',
    async ({ userId, query }) => {
      const smsLogs = getCollection<SmsLog>('smsLogs');

      const filter: any = { userId: new ObjectId(userId) };

      if (query.messageType) {
        filter.messageType = query.messageType;
      }

      if (query.from) {
        filter.createdAt = { ...filter.createdAt, $gte: new Date(query.from) };
      }
      if (query.to) {
        filter.createdAt = { ...filter.createdAt, $lte: new Date(query.to) };
      }

      const limit = Math.min(query.limit || 50, 200);
      const skip = query.offset || 0;

      const logs = await smsLogs
        .find(filter)
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(limit)
        .toArray();

      const total = await smsLogs.countDocuments(filter);

      return {
        logs: logs.map((l) => ({
          id: l._id!.toString(),
          recipientPhone: l.recipientPhone,
          recipientName: l.recipientName,
          latitude: l.latitude,
          longitude: l.longitude,
          accuracy: l.accuracy,
          messageType: l.messageType,
          status: l.status,
          googleMapsLink: l.googleMapsLink,
          triggerReason: l.triggerReason,
          offlineDuration: l.offlineDuration,
          createdAt: l.createdAt,
          sentAt: l.sentAt,
        })),
        total,
        limit,
        offset: skip,
      };
    },
    {
      query: t.Object({
        messageType: t.Optional(
          t.Union([
            t.Literal('manual'),
            t.Literal('auto_fallback'),
            t.Literal('sos'),
            t.Literal('scheduled'),
          ])
        ),
        from: t.Optional(t.String()),
        to: t.Optional(t.String()),
        limit: t.Optional(t.Number({ minimum: 1, maximum: 200 })),
        offset: t.Optional(t.Number({ minimum: 0 })),
      }),
      detail: {
        tags: ['SMS'],
        summary: 'Get SMS logs',
      },
    }
  )
  // Get SMS statistics
  .get(
    '/stats',
    async ({ userId, query }) => {
      const smsLogs = getCollection<SmsLog>('smsLogs');

      const userObjectId = new ObjectId(userId);

      // Date range filter
      const dateFilter: any = {};
      if (query.from) {
        dateFilter.$gte = new Date(query.from);
      }
      if (query.to) {
        dateFilter.$lte = new Date(query.to);
      }

      const matchStage: any = { userId: userObjectId };
      if (Object.keys(dateFilter).length > 0) {
        matchStage.createdAt = dateFilter;
      }

      // Aggregate stats
      const pipeline = [
        { $match: matchStage },
        {
          $group: {
            _id: '$messageType',
            count: { $sum: 1 },
            lastSent: { $max: '$createdAt' },
          },
        },
      ];

      const stats = await smsLogs.aggregate(pipeline).toArray();

      const result: Record<string, { count: number; lastSent: Date | null }> = {
        manual: { count: 0, lastSent: null },
        auto_fallback: { count: 0, lastSent: null },
        sos: { count: 0, lastSent: null },
        scheduled: { count: 0, lastSent: null },
      };

      for (const stat of stats) {
        result[stat._id] = {
          count: stat.count,
          lastSent: stat.lastSent,
        };
      }

      const total = Object.values(result).reduce((sum, s) => sum + s.count, 0);

      return {
        total,
        byType: result,
      };
    },
    {
      query: t.Object({
        from: t.Optional(t.String()),
        to: t.Optional(t.String()),
      }),
      detail: {
        tags: ['SMS'],
        summary: 'Get SMS statistics',
      },
    }
  );
