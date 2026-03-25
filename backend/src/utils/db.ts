import { MongoClient, Db, Collection, ObjectId } from 'mongodb';

let client: MongoClient | null = null;
let db: Db | null = null;

export async function connectDatabase(): Promise<Db> {
  if (db) {
    return db;
  }

  const uri = process.env.MONGODB_URI || 'mongodb://localhost:27017/location-sharing';

  try {
    client = new MongoClient(uri);
    await client.connect();
    db = client.db();

    console.log('✅ Connected to MongoDB');

    // Create indexes
    await createIndexes(db);

    return db;
  } catch (error) {
    console.error('❌ Failed to connect to MongoDB:', error);
    throw error;
  }
}

async function createIndexes(db: Db): Promise<void> {
  // Users collection indexes
  const users = db.collection('users');
  await users.createIndex({ email: 1 }, { unique: true, sparse: true });
  await users.createIndex({ phone: 1 }, { unique: true });
  await users.createIndex({ googleId: 1 }, { unique: true, sparse: true });
  await users.createIndex({ appleId: 1 }, { unique: true, sparse: true });
  await users.createIndex({ firebaseUid: 1 }, { unique: true });

  // Friends collection indexes
  const friends = db.collection('friends');
  await friends.createIndex({ userId: 1, friendId: 1 }, { unique: true });
  await friends.createIndex({ userId: 1, status: 1 });
  await friends.createIndex({ friendId: 1, status: 1 });

  // Locations collection indexes
  const locations = db.collection('locations');
  await locations.createIndex({ userId: 1, timestamp: -1 });
  await locations.createIndex({ location: '2dsphere' });
  await locations.createIndex(
    { timestamp: 1 },
    { expireAfterSeconds: 30 * 24 * 60 * 60 } // 30 days TTL
  );

  // Emergency contacts collection indexes
  const emergencyContacts = db.collection('emergencyContacts');
  await emergencyContacts.createIndex({ userId: 1 });

  // SMS logs collection indexes
  const smsLogs = db.collection('smsLogs');
  await smsLogs.createIndex({ userId: 1, createdAt: -1 });
  await smsLogs.createIndex({ status: 1 });

  // Active sessions collection indexes
  const activeSessions = db.collection('activeSessions');
  await activeSessions.createIndex({ userId: 1 });
  await activeSessions.createIndex({ socketId: 1 }, { unique: true });
  await activeSessions.createIndex(
    { expiresAt: 1 },
    { expireAfterSeconds: 0 } // TTL based on expiresAt field
  );

  console.log('✅ Database indexes created');
}

export function getDb(): Db {
  if (!db) {
    throw new Error('Database not connected. Call connectDatabase() first.');
  }
  return db;
}

export function getCollection<T extends Document>(name: string): Collection<T> {
  return getDb().collection<T>(name);
}

export async function closeDatabase(): Promise<void> {
  if (client) {
    await client.close();
    client = null;
    db = null;
    console.log('✅ MongoDB connection closed');
  }
}

// Type helpers
export { ObjectId };
export type { Db, Collection };
