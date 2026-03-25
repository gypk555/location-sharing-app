import { Elysia, t } from 'elysia';
import { getCollection, ObjectId } from '../utils/db';
import { Friend } from '../models/Friend';
import { Location, createLocation } from '../models/Location';

interface ActiveConnection {
  id: string;
  userId: string;
  isSharing: boolean;
  lastLocation?: {
    latitude: number;
    longitude: number;
    accuracy: number;
    timestamp: Date;
  };
}

// In-memory store for active connections
// In production, use Redis for multi-server support
const activeConnections = new Map<string, ActiveConnection>();
const userToSocket = new Map<string, string>(); // userId -> socketId

export const setupWebSocket = new Elysia()
  .ws('/ws', {
    body: t.Object({
      type: t.String(),
      payload: t.Optional(t.Any()),
    }),
    message: t.Object({
      type: t.String(),
      payload: t.Optional(t.Any()),
    }),

    // Handle new connection
    open(ws) {
      const socketId = ws.id;
      console.log(`[WebSocket] New connection: ${socketId}`);

      activeConnections.set(socketId, {
        id: socketId,
        userId: '',
        isSharing: false,
      });
    },

    // Handle messages
    async message(ws, message) {
      const socketId = ws.id;
      const connection = activeConnections.get(socketId);

      if (!connection) {
        ws.send(JSON.stringify({ type: 'error', payload: 'Connection not found' }));
        return;
      }

      try {
        switch (message.type) {
          case 'authenticate':
            await handleAuthenticate(ws, connection, message.payload);
            break;

          case 'location:update':
            await handleLocationUpdate(ws, connection, message.payload);
            break;

          case 'location:start-sharing':
            handleStartSharing(ws, connection);
            break;

          case 'location:stop-sharing':
            handleStopSharing(ws, connection);
            break;

          case 'ping':
            ws.send(JSON.stringify({ type: 'pong', payload: Date.now() }));
            break;

          default:
            ws.send(
              JSON.stringify({
                type: 'error',
                payload: `Unknown message type: ${message.type}`,
              })
            );
        }
      } catch (error: any) {
        console.error(`[WebSocket] Error handling message:`, error);
        ws.send(
          JSON.stringify({
            type: 'error',
            payload: error.message || 'Internal error',
          })
        );
      }
    },

    // Handle disconnection
    close(ws) {
      const socketId = ws.id;
      const connection = activeConnections.get(socketId);

      if (connection && connection.userId) {
        // Notify friends that user went offline
        notifyFriendsOffline(connection.userId);
        userToSocket.delete(connection.userId);
      }

      activeConnections.delete(socketId);
      console.log(`[WebSocket] Connection closed: ${socketId}`);
    },
  });

// Authentication handler
async function handleAuthenticate(
  ws: any,
  connection: ActiveConnection,
  payload: any
) {
  if (!payload?.userId) {
    ws.send(JSON.stringify({ type: 'error', payload: 'Missing userId' }));
    return;
  }

  connection.userId = payload.userId;
  userToSocket.set(payload.userId, connection.id);

  // Notify friends that user is online
  await notifyFriendsOnline(payload.userId);

  ws.send(
    JSON.stringify({
      type: 'authenticated',
      payload: { userId: payload.userId },
    })
  );

  console.log(`[WebSocket] User authenticated: ${payload.userId}`);
}

// Location update handler
async function handleLocationUpdate(
  ws: any,
  connection: ActiveConnection,
  payload: any
) {
  if (!connection.userId) {
    ws.send(
      JSON.stringify({ type: 'error', payload: 'Not authenticated' })
    );
    return;
  }

  if (!connection.isSharing) {
    ws.send(
      JSON.stringify({ type: 'error', payload: 'Location sharing not enabled' })
    );
    return;
  }

  const { latitude, longitude, accuracy, altitude, heading, speed } = payload;

  // Update connection's last location
  connection.lastLocation = {
    latitude,
    longitude,
    accuracy,
    timestamp: new Date(),
  };

  // Save to database (throttled - only every 30 seconds in production)
  const locations = getCollection<Location>('locations');
  const location = createLocation(new ObjectId(connection.userId), {
    latitude,
    longitude,
    accuracy,
    altitude,
    heading,
    speed,
  });
  await locations.insertOne(location);

  // Broadcast to friends
  await broadcastLocationToFriends(connection.userId, {
    latitude,
    longitude,
    accuracy,
    timestamp: new Date(),
  });

  ws.send(JSON.stringify({ type: 'location:ack', payload: { timestamp: Date.now() } }));
}

// Start sharing handler
function handleStartSharing(ws: any, connection: ActiveConnection) {
  if (!connection.userId) {
    ws.send(JSON.stringify({ type: 'error', payload: 'Not authenticated' }));
    return;
  }

  connection.isSharing = true;

  // Notify friends
  notifyFriendsStartedSharing(connection.userId);

  ws.send(JSON.stringify({ type: 'location:sharing-started' }));
  console.log(`[WebSocket] User started sharing: ${connection.userId}`);
}

// Stop sharing handler
function handleStopSharing(ws: any, connection: ActiveConnection) {
  if (!connection.userId) {
    ws.send(JSON.stringify({ type: 'error', payload: 'Not authenticated' }));
    return;
  }

  connection.isSharing = false;
  connection.lastLocation = undefined;

  // Notify friends
  notifyFriendsStoppedSharing(connection.userId);

  ws.send(JSON.stringify({ type: 'location:sharing-stopped' }));
  console.log(`[WebSocket] User stopped sharing: ${connection.userId}`);
}

// Helper: Get friend socket IDs
async function getFriendSocketIds(userId: string): Promise<string[]> {
  const friends = getCollection<Friend>('friends');
  const userObjectId = new ObjectId(userId);

  const friendRecords = await friends
    .find({
      $or: [{ userId: userObjectId }, { friendId: userObjectId }],
      status: 'accepted',
      canViewLocation: true,
    })
    .toArray();

  const friendUserIds = friendRecords.map((f) =>
    f.userId.equals(userObjectId)
      ? f.friendId.toString()
      : f.userId.toString()
  );

  return friendUserIds
    .map((id) => userToSocket.get(id))
    .filter((socketId): socketId is string => !!socketId);
}

// Broadcast location to friends
async function broadcastLocationToFriends(
  userId: string,
  location: { latitude: number; longitude: number; accuracy: number; timestamp: Date }
) {
  const friendSocketIds = await getFriendSocketIds(userId);

  const message = JSON.stringify({
    type: 'location:receive',
    payload: {
      userId,
      ...location,
    },
  });

  // Note: In Elysia, we can't directly send to specific sockets from outside
  // This would need Redis pub/sub in production
  // For now, this is a placeholder for the concept
  console.log(
    `[WebSocket] Broadcasting location from ${userId} to ${friendSocketIds.length} friends`
  );
}

// Notify friends user is online
async function notifyFriendsOnline(userId: string) {
  const friendSocketIds = await getFriendSocketIds(userId);
  console.log(`[WebSocket] Notifying ${friendSocketIds.length} friends that ${userId} is online`);
}

// Notify friends user is offline
async function notifyFriendsOffline(userId: string) {
  const friendSocketIds = await getFriendSocketIds(userId);
  console.log(
    `[WebSocket] Notifying ${friendSocketIds.length} friends that ${userId} is offline`
  );
}

// Notify friends user started sharing
async function notifyFriendsStartedSharing(userId: string) {
  const friendSocketIds = await getFriendSocketIds(userId);
  console.log(
    `[WebSocket] Notifying ${friendSocketIds.length} friends that ${userId} started sharing`
  );
}

// Notify friends user stopped sharing
async function notifyFriendsStoppedSharing(userId: string) {
  const friendSocketIds = await getFriendSocketIds(userId);
  console.log(
    `[WebSocket] Notifying ${friendSocketIds.length} friends that ${userId} stopped sharing`
  );
}
