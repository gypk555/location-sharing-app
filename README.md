# Location Sharing App with SMS Fallback

A cross-platform mobile app for real-time location sharing with SMS fallback when offline.

## Features

- **Real-time Location Sharing** - Share your location with friends via WebSocket when online
- **SMS Fallback** - Automatically send location via SMS when offline
- **Emergency SOS** - Quick SOS button to send location to preset emergency contacts
- **Scheduled SMS** - Send periodic location updates via SMS
- **Friend Management** - Add friends and manage location sharing permissions
- **Location History** - View and export your location history

## Tech Stack

### Mobile (React Native)
- React Native with TypeScript
- React Navigation for routing
- Firebase Auth for authentication (Phone OTP, Email, Google, Apple)
- Background location tracking
- Native SMS module for direct SMS sending (Android)

### Backend (Elysia/Bun)
- Elysia framework with Bun runtime
- MongoDB for database
- WebSocket for real-time updates
- JWT authentication
- Twilio for server-side SMS (SOS backup)

## Project Structure

```
location-sharing-app/
├── mobile/                 # React Native app
│   ├── src/
│   │   ├── modules/       # Core modules (auth, location, sms, network)
│   │   ├── screens/       # Screen components
│   │   ├── navigation/    # Navigation setup
│   │   ├── components/    # Reusable components
│   │   └── hooks/         # Custom hooks
│   └── package.json
│
├── backend/               # Elysia backend
│   ├── src/
│   │   ├── routes/       # API routes
│   │   ├── models/       # MongoDB models
│   │   ├── socket/       # WebSocket handlers
│   │   ├── middleware/   # Auth middleware
│   │   └── utils/        # Database utils
│   └── package.json
│
└── shared/               # Shared TypeScript types
    └── types/
```

## Getting Started

### Prerequisites

- Node.js 18+
- Bun runtime
- MongoDB (local or Atlas)
- Firebase project (for authentication)
- Android Studio / Xcode (for mobile development)

### Backend Setup

```bash
cd backend

# Install dependencies
bun install

# Copy environment file
cp .env.example .env

# Edit .env with your configuration
# - MongoDB URI
# - JWT secrets
# - Firebase credentials
# - Twilio credentials (optional)

# Start development server
bun run dev
```

### Mobile Setup

```bash
cd mobile

# Install dependencies
npm install

# Copy environment file
cp .env.example .env

# Edit .env with your configuration
# - API URL
# - Mapbox token

# Install iOS pods (Mac only)
cd ios && pod install && cd ..

# Start Metro bundler
npm start

# Run on Android
npm run android

# Run on iOS
npm run ios
```

## Configuration

### Firebase Setup

1. Create a Firebase project
2. Enable Authentication methods:
   - Phone (for OTP)
   - Email/Password
   - Google Sign-In
   - Apple Sign-In (iOS only)
3. Download and add configuration files:
   - `google-services.json` for Android
   - `GoogleService-Info.plist` for iOS

### Twilio Setup (Optional)

For server-side SOS SMS:
1. Create a Twilio account
2. Get Account SID, Auth Token, and Phone Number
3. Add to backend `.env`

### Mapbox Setup

For map visualization:
1. Create a Mapbox account
2. Get Access Token
3. Add to mobile `.env`

## SMS Features

### Manual Share
User can manually share their location via SMS with a single tap.

### Auto-Fallback
When the app detects no internet connectivity for 30 seconds (configurable), it automatically sends the user's location via SMS to configured contacts.

### Emergency SOS
Long-press (3 seconds) the SOS button to send location to all emergency contacts. Includes:
- Google Maps link
- Raw coordinates
- Accuracy info
- Custom emergency message

### Scheduled Updates
Users can configure periodic SMS updates (e.g., every 30 minutes) to selected contacts.

## API Endpoints

### Authentication
- `POST /api/auth/sync` - Sync Firebase user
- `POST /api/auth/verify-token` - Verify JWT
- `POST /api/auth/refresh` - Refresh token

### Users
- `GET /api/users/me` - Get profile
- `PUT /api/users/me` - Update profile
- `PUT /api/users/me/sms-settings` - Update SMS settings
- `GET /api/users/search` - Search users

### Friends
- `GET /api/friends` - List friends
- `POST /api/friends/request` - Send request
- `POST /api/friends/:id/accept` - Accept request
- `DELETE /api/friends/:id` - Remove friend
- `PUT /api/friends/:id/permissions` - Update permissions

### Locations
- `POST /api/locations` - Save location
- `GET /api/locations/friends` - Get friends' locations
- `GET /api/locations/history` - Get history
- `DELETE /api/locations/history` - Delete history

### Emergency
- `GET /api/emergency/contacts` - List contacts
- `POST /api/emergency/contacts` - Add contact
- `PUT /api/emergency/contacts/:id` - Update contact
- `DELETE /api/emergency/contacts/:id` - Delete contact
- `POST /api/emergency/sos` - Trigger SOS

### SMS
- `POST /api/sms/log` - Log SMS send
- `GET /api/sms/logs` - Get SMS logs
- `GET /api/sms/stats` - Get statistics

## WebSocket Events

- `authenticate` - Authenticate connection
- `location:update` - Send location update
- `location:receive` - Receive friend's location
- `location:start-sharing` - Start sharing
- `location:stop-sharing` - Stop sharing
- `friend:online` - Friend came online
- `friend:offline` - Friend went offline

## Security Considerations

- All API communication over HTTPS
- JWT tokens with short expiration (15 min)
- Phone numbers verified via OTP
- Location permissions required
- SMS rate limiting (10/hour)
- Emergency SOS cooldown (1 minute)

## iOS Limitations

iOS does not allow direct SMS sending without user interaction:
- Manual share opens SMS composer pre-filled
- Auto-fallback shows notification prompting user
- SOS can use server-side Twilio as backup

## License

MIT
