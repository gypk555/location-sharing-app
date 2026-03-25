import { Elysia, t } from 'elysia';
import { getCollection, ObjectId } from '../utils/db';
import { EmergencyContact, createEmergencyContact } from '../models/EmergencyContact';
import { authMiddleware } from '../middleware/auth';

const MAX_EMERGENCY_CONTACTS = 5;

export const emergencyRoutes = new Elysia({ prefix: '/emergency' })
  .use(authMiddleware)
  // List emergency contacts
  .get(
    '/contacts',
    async ({ userId }) => {
      const contacts = getCollection<EmergencyContact>('emergencyContacts');

      const results = await contacts
        .find({ userId: new ObjectId(userId) })
        .toArray();

      return {
        contacts: results.map((c) => ({
          id: c._id!.toString(),
          name: c.name,
          phone: c.phone,
          email: c.email,
          relationship: c.relationship,
          enabledForSos: c.enabledForSos,
          customMessage: c.customMessage,
        })),
      };
    },
    {
      detail: {
        tags: ['Emergency'],
        summary: 'List emergency contacts',
      },
    }
  )
  // Add emergency contact
  .post(
    '/contacts',
    async ({ userId, body, set }) => {
      const contacts = getCollection<EmergencyContact>('emergencyContacts');

      // Check limit
      const count = await contacts.countDocuments({
        userId: new ObjectId(userId),
      });

      if (count >= MAX_EMERGENCY_CONTACTS) {
        set.status = 400;
        return {
          error: `Maximum ${MAX_EMERGENCY_CONTACTS} emergency contacts allowed`,
        };
      }

      const contact = createEmergencyContact(new ObjectId(userId), {
        name: body.name,
        phone: body.phone,
        email: body.email,
        relationship: body.relationship,
        customMessage: body.customMessage,
      });

      const result = await contacts.insertOne(contact);

      return {
        id: result.insertedId.toString(),
        message: 'Emergency contact added',
      };
    },
    {
      body: t.Object({
        name: t.String({ minLength: 1 }),
        phone: t.String({ minLength: 5 }),
        email: t.Optional(t.String()),
        relationship: t.Optional(
          t.Union([
            t.Literal('family'),
            t.Literal('friend'),
            t.Literal('partner'),
            t.Literal('coworker'),
            t.Literal('other'),
          ])
        ),
        customMessage: t.Optional(t.String()),
      }),
      detail: {
        tags: ['Emergency'],
        summary: 'Add emergency contact',
      },
    }
  )
  // Update emergency contact
  .put(
    '/contacts/:id',
    async ({ userId, params, body, set }) => {
      const contacts = getCollection<EmergencyContact>('emergencyContacts');

      const updateData: Partial<EmergencyContact> = {
        updatedAt: new Date(),
      };

      if (body.name !== undefined) updateData.name = body.name;
      if (body.phone !== undefined) updateData.phone = body.phone;
      if (body.email !== undefined) updateData.email = body.email;
      if (body.relationship !== undefined)
        updateData.relationship = body.relationship;
      if (body.enabledForSos !== undefined)
        updateData.enabledForSos = body.enabledForSos;
      if (body.customMessage !== undefined)
        updateData.customMessage = body.customMessage;

      const result = await contacts.updateOne(
        {
          _id: new ObjectId(params.id),
          userId: new ObjectId(userId),
        },
        { $set: updateData }
      );

      if (result.matchedCount === 0) {
        set.status = 404;
        return { error: 'Contact not found' };
      }

      return { success: true };
    },
    {
      params: t.Object({
        id: t.String(),
      }),
      body: t.Object({
        name: t.Optional(t.String({ minLength: 1 })),
        phone: t.Optional(t.String({ minLength: 5 })),
        email: t.Optional(t.String()),
        relationship: t.Optional(
          t.Union([
            t.Literal('family'),
            t.Literal('friend'),
            t.Literal('partner'),
            t.Literal('coworker'),
            t.Literal('other'),
          ])
        ),
        enabledForSos: t.Optional(t.Boolean()),
        customMessage: t.Optional(t.String()),
      }),
      detail: {
        tags: ['Emergency'],
        summary: 'Update emergency contact',
      },
    }
  )
  // Delete emergency contact
  .delete(
    '/contacts/:id',
    async ({ userId, params, set }) => {
      const contacts = getCollection<EmergencyContact>('emergencyContacts');

      const result = await contacts.deleteOne({
        _id: new ObjectId(params.id),
        userId: new ObjectId(userId),
      });

      if (result.deletedCount === 0) {
        set.status = 404;
        return { error: 'Contact not found' };
      }

      return { success: true };
    },
    {
      params: t.Object({
        id: t.String(),
      }),
      detail: {
        tags: ['Emergency'],
        summary: 'Delete emergency contact',
      },
    }
  )
  // Trigger SOS via server (sends SMS via Twilio)
  .post(
    '/sos',
    async ({ userId, body, set }) => {
      const contacts = getCollection<EmergencyContact>('emergencyContacts');

      // Get enabled emergency contacts
      const emergencyContacts = await contacts
        .find({
          userId: new ObjectId(userId),
          enabledForSos: true,
        })
        .toArray();

      if (emergencyContacts.length === 0) {
        set.status = 400;
        return { error: 'No emergency contacts configured' };
      }

      // Format SOS message
      const lat = body.latitude.toFixed(6);
      const lng = body.longitude.toFixed(6);
      const mapsLink = `https://maps.google.com/?q=${lat},${lng}`;

      const results: Array<{ contact: string; success: boolean; error?: string }> = [];

      // Send SMS via Twilio (if configured)
      const twilioSid = process.env.TWILIO_ACCOUNT_SID;
      const twilioToken = process.env.TWILIO_AUTH_TOKEN;
      const twilioPhone = process.env.TWILIO_PHONE_NUMBER;

      if (twilioSid && twilioToken && twilioPhone) {
        const twilio = require('twilio')(twilioSid, twilioToken);

        for (const contact of emergencyContacts) {
          const message = [
            '!!! EMERGENCY SOS !!!',
            '',
            contact.customMessage || 'I need help! This is my current location:',
            '',
            `LOCATION: ${mapsLink}`,
            '',
            `Coordinates: ${lat}, ${lng}`,
            `Accuracy: ~${Math.round(body.accuracy)}m`,
            `Time: ${new Date().toLocaleString()}`,
            '',
            '- Sent via Location Sharing App',
          ].join('\n');

          try {
            await twilio.messages.create({
              body: message,
              from: twilioPhone,
              to: contact.phone,
            });
            results.push({ contact: contact.name, success: true });
          } catch (error: any) {
            results.push({
              contact: contact.name,
              success: false,
              error: error.message,
            });
          }
        }
      } else {
        // Twilio not configured
        return {
          success: false,
          message: 'Server SMS not configured. Use client-side SMS.',
          contacts: emergencyContacts.map((c) => ({
            name: c.name,
            phone: c.phone,
          })),
        };
      }

      const successCount = results.filter((r) => r.success).length;

      return {
        success: successCount > 0,
        sentTo: successCount,
        total: emergencyContacts.length,
        results,
      };
    },
    {
      body: t.Object({
        latitude: t.Number({ minimum: -90, maximum: 90 }),
        longitude: t.Number({ minimum: -180, maximum: 180 }),
        accuracy: t.Number({ minimum: 0 }),
      }),
      detail: {
        tags: ['Emergency'],
        summary: 'Trigger SOS alert via server',
      },
    }
  );
