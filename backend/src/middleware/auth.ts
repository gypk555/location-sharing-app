import { Elysia } from 'elysia';
import { jwt } from '@elysiajs/jwt';

export const authMiddleware = new Elysia({ name: 'authMiddleware' })
  .use(
    jwt({
      name: 'jwt',
      secret: process.env.JWT_SECRET || 'development-secret-change-me',
    })
  )
  .derive(async ({ headers, jwt, set }) => {
    const authHeader = headers.authorization;

    if (!authHeader?.startsWith('Bearer ')) {
      set.status = 401;
      throw new Error('Missing or invalid authorization header');
    }

    const token = authHeader.slice(7);

    try {
      const payload = await jwt.verify(token);

      if (!payload || !payload.sub) {
        set.status = 401;
        throw new Error('Invalid token');
      }

      return {
        userId: payload.sub as string,
        firebaseUid: payload.uid as string,
      };
    } catch (error) {
      set.status = 401;
      throw new Error('Invalid or expired token');
    }
  })
  .onError(({ code, error, set }) => {
    if (error.message === 'Missing or invalid authorization header') {
      set.status = 401;
      return { error: 'Unauthorized', message: 'Missing or invalid authorization header' };
    }
    if (error.message === 'Invalid token' || error.message === 'Invalid or expired token') {
      set.status = 401;
      return { error: 'Unauthorized', message: 'Invalid or expired token' };
    }
  });
