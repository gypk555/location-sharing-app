import { Elysia } from 'elysia';
import { cors } from '@elysiajs/cors';
import { jwt } from '@elysiajs/jwt';
import { swagger } from '@elysiajs/swagger';

import { connectDatabase } from './utils/db';
import { authRoutes } from './routes/auth';
import { userRoutes } from './routes/users';
import { friendRoutes } from './routes/friends';
import { locationRoutes } from './routes/locations';
import { emergencyRoutes } from './routes/emergency';
import { smsRoutes } from './routes/sms';
import { setupWebSocket } from './socket';

const PORT = process.env.PORT || 3001;

// Initialize database connection
await connectDatabase();

const app = new Elysia()
  // Swagger documentation
  .use(
    swagger({
      documentation: {
        info: {
          title: 'Location Sharing API',
          version: '1.0.0',
          description: 'API for location sharing app with SMS fallback',
        },
        tags: [
          { name: 'Auth', description: 'Authentication endpoints' },
          { name: 'Users', description: 'User management' },
          { name: 'Friends', description: 'Friend management' },
          { name: 'Locations', description: 'Location tracking' },
          { name: 'Emergency', description: 'Emergency/SOS features' },
          { name: 'SMS', description: 'SMS logging' },
        ],
      },
    })
  )
  // CORS
  .use(
    cors({
      origin: process.env.CORS_ORIGIN || 'http://localhost:3000',
      credentials: true,
    })
  )
  // JWT
  .use(
    jwt({
      name: 'jwt',
      secret: process.env.JWT_SECRET || 'development-secret-change-me',
      exp: '15m',
    })
  )
  .use(
    jwt({
      name: 'refreshJwt',
      secret: process.env.JWT_REFRESH_SECRET || 'refresh-secret-change-me',
      exp: '7d',
    })
  )
  // Health check
  .get('/health', () => ({ status: 'ok', timestamp: new Date().toISOString() }))
  // API routes
  .group('/api', (app) =>
    app
      .use(authRoutes)
      .use(userRoutes)
      .use(friendRoutes)
      .use(locationRoutes)
      .use(emergencyRoutes)
      .use(smsRoutes)
  )
  // WebSocket setup
  .use(setupWebSocket)
  // Error handling
  .onError(({ code, error, set }) => {
    console.error(`[Error] ${code}:`, error);

    if (code === 'NOT_FOUND') {
      set.status = 404;
      return { error: 'Not Found' };
    }

    if (code === 'VALIDATION') {
      set.status = 400;
      return { error: 'Validation Error', details: error.message };
    }

    set.status = 500;
    return { error: 'Internal Server Error' };
  })
  .listen(PORT);

console.log(`
🚀 Location Sharing API is running!

   📡 HTTP: http://localhost:${PORT}
   📚 Docs: http://localhost:${PORT}/swagger
   🔌 WebSocket: ws://localhost:${PORT}/ws
`);

export type App = typeof app;
