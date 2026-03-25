import { Elysia, t } from 'elysia';
import { getCollection, ObjectId } from '../utils/db';
import { User, createUser, defaultSmsSettings } from '../models/User';

export const authRoutes = new Elysia({ prefix: '/auth' })
  // Sync Firebase user with backend
  .post(
    '/sync',
    async ({ body, jwt, set }) => {
      const users = getCollection<User>('users');

      // Check if user exists
      let user = await users.findOne({ firebaseUid: body.uid });

      if (user) {
        // Update existing user
        const updateData: Partial<User> = {
          lastActiveAt: new Date(),
          updatedAt: new Date(),
        };

        if (body.name) updateData.name = body.name;
        if (body.email) updateData.email = body.email;
        if (body.phone) updateData.phone = body.phone;
        if (body.photoUrl) updateData.profilePicture = body.photoUrl;

        await users.updateOne({ _id: user._id }, { $set: updateData });
        user = await users.findOne({ _id: user._id });
      } else {
        // Create new user
        const newUser = createUser({
          firebaseUid: body.uid,
          email: body.email,
          phone: body.phone || '',
          name: body.name || 'User',
          profilePicture: body.photoUrl,
          googleId: body.authProvider === 'google' ? body.uid : undefined,
          appleId: body.authProvider === 'apple' ? body.uid : undefined,
        });

        const result = await users.insertOne(newUser);
        user = await users.findOne({ _id: result.insertedId });
      }

      if (!user) {
        set.status = 500;
        return { error: 'Failed to create/update user' };
      }

      // Generate JWT tokens
      const accessToken = await jwt.sign({
        sub: user._id!.toString(),
        uid: user.firebaseUid,
      });

      return {
        user: {
          id: user._id!.toString(),
          uid: user.firebaseUid,
          email: user.email,
          phone: user.phone,
          name: user.name,
          profilePicture: user.profilePicture,
          locationSharingEnabled: user.locationSharingEnabled,
          smsSettings: user.smsSettings,
        },
        accessToken,
      };
    },
    {
      body: t.Object({
        uid: t.String(),
        email: t.Optional(t.String()),
        phone: t.Optional(t.String()),
        name: t.Optional(t.String()),
        photoUrl: t.Optional(t.String()),
        authProvider: t.Union([
          t.Literal('phone'),
          t.Literal('email'),
          t.Literal('google'),
          t.Literal('apple'),
        ]),
      }),
      detail: {
        tags: ['Auth'],
        summary: 'Sync Firebase user with backend',
        description:
          'Called after Firebase authentication to sync user data with backend',
      },
    }
  )
  // Verify token
  .post(
    '/verify-token',
    async ({ headers, jwt, set }) => {
      const authHeader = headers.authorization;
      if (!authHeader?.startsWith('Bearer ')) {
        set.status = 401;
        return { error: 'Missing authorization header' };
      }

      const token = authHeader.slice(7);
      const payload = await jwt.verify(token);

      if (!payload) {
        set.status = 401;
        return { error: 'Invalid token' };
      }

      return { valid: true, payload };
    },
    {
      detail: {
        tags: ['Auth'],
        summary: 'Verify JWT token',
      },
    }
  )
  // Refresh token
  .post(
    '/refresh',
    async ({ body, jwt, refreshJwt, set }) => {
      const payload = await refreshJwt.verify(body.refreshToken);

      if (!payload) {
        set.status = 401;
        return { error: 'Invalid refresh token' };
      }

      const accessToken = await jwt.sign({
        sub: payload.sub,
        uid: payload.uid,
      });

      return { accessToken };
    },
    {
      body: t.Object({
        refreshToken: t.String(),
      }),
      detail: {
        tags: ['Auth'],
        summary: 'Refresh access token',
      },
    }
  );
