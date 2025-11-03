# NoBS Dating

A straightforward dating app with no BS. Built with Flutter for the frontend and Node.js/TypeScript/Express microservices for the backend.

## Features

- **Passwordless Authentication**: Sign in with Apple/Google using JWT tokens
- **Subscription Gating**: App access controlled by RevenueCat's "premium_access" entitlement
- **Three Main Tabs**:
  - **Discovery**: Browse and swipe on profiles
  - **Matches**: View your matches and chat history
  - **Profile**: Manage your profile and subscription
- **Paywall**: Users without active subscription see a paywall blocking Discovery and Matches tabs
- **Microservices Backend**: Three separate services (Auth, Profile, Chat) with Docker support

## Architecture

### Backend (Node.js/TypeScript/Express)
- **Auth Service** (Port 3001): Handles Sign in with Apple/Google and JWT token generation
- **Profile Service** (Port 3002): Manages user profiles (stub CRUD operations)
- **Chat Service** (Port 3003): Handles matches and messages (placeholder implementation)
- **Database**: PostgreSQL (containerized)

### Frontend (Flutter)
- **State Management**: Provider pattern
- **Authentication**: Sign in with Apple/Google integration
- **Subscription**: RevenueCat SDK for subscription management
- **UI**: Material Design with three main screens

## Prerequisites

### Backend
- Node.js 18+
- Docker and Docker Compose
- PostgreSQL (via Docker)

### Frontend
- Flutter SDK 3.0+
- Xcode (for iOS development)
- Android Studio (for Android development)

## Quick Start

### Backend Setup

1. **Copy environment file and configure secrets:**
   ```bash
   cp .env.example .env
   # Edit .env and set POSTGRES_PASSWORD and JWT_SECRET
   ```

2. **Start all services with Docker Compose:**
   ```bash
   ./start-backend.sh
   # or: docker-compose up --build
   ```

   This will start:
   - PostgreSQL database (port 5432)
   - Auth service (port 3001)
   - Profile service (port 3002)
   - Chat service (port 3003)

### Frontend Setup

1. **Install dependencies:**
   ```bash
   cd frontend
   flutter pub get
   ```

2. **Run the app:**
   ```bash
   flutter run --dart-define=REVENUECAT_API_KEY=YOUR_KEY
   ```

For detailed setup instructions including RevenueCat configuration, Apple/Google Sign In setup, and production deployment, see **[SETUP.md](SETUP.md)**.

## API Endpoints

### Auth Service (Port 3001)
- `GET /health` - Health check
- `POST /auth/apple` - Sign in with Apple
- `POST /auth/google` - Sign in with Google
- `POST /auth/verify` - Verify JWT token

### Profile Service (Port 3002)
- `GET /health` - Health check
- `POST /profile` - Create/update profile
- `GET /profile/:userId` - Get profile by user ID
- `PUT /profile/:userId` - Update profile
- `DELETE /profile/:userId` - Delete profile
- `GET /profiles/discover` - Get random profiles for discovery

### Chat Service (Port 3003)
- `GET /health` - Health check
- `GET /matches/:userId` - Get matches for a user
- `POST /matches` - Create a match
- `GET /messages/:matchId` - Get messages for a match
- `POST /messages` - Send a message

## Development

### Backend Development
Each service can be run independently for development:
```bash
cd backend/<service-name>
npm run dev
```

Build for production:
```bash
npm run build
npm start
```

### Frontend Development
Run in development mode:
```bash
cd frontend
flutter run
```

Build for production:
```bash
# iOS
flutter build ios

# Android
flutter build apk
```

## Testing

### Backend
Currently using stub implementations. To add tests:
```bash
cd backend/<service-name>
npm test
```

### Frontend
Run Flutter tests:
```bash
cd frontend
flutter test
```

## Environment Variables

### Backend Services
Create `.env` files based on `.env.example` in each service directory:

- `PORT`: Service port number
- `JWT_SECRET`: Secret key for JWT signing (change in production!)
- `DATABASE_URL`: PostgreSQL connection string

## Security Notes

⚠️ **IMPORTANT**: This implementation uses stub authentication for demonstration purposes. Before deploying to production:

1. **Environment Variables**: Never commit `.env` files. The auth service will now exit if `JWT_SECRET` is not set.
2. **Generate Strong Secrets**: 
   ```bash
   openssl rand -base64 64  # For JWT_SECRET
   ```
3. **Token Verification**: Implement proper Apple identity token and Google ID token verification server-side.
4. **Database Security**: Use strong passwords and enable SSL connections for PostgreSQL.
5. **HTTPS**: Use HTTPS for all API endpoints in production.
6. **API Keys**: Store RevenueCat API keys securely and use different keys for development/production.

See **[SETUP.md](SETUP.md)** for complete security checklist.

## Subscription Flow

1. User signs in with Apple/Google
2. App checks for "premium_access" entitlement via RevenueCat
3. If entitlement is inactive:
   - Show paywall screen
   - Block access to Discovery and Matches tabs
   - Only Profile tab is accessible
4. User subscribes through paywall
5. RevenueCat updates entitlement
6. App unlocks all features

## License

ISC

## Contributing

This is a demonstration project. Feel free to fork and modify as needed.