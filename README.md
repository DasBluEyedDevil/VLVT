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

## Setup Instructions

### Backend Setup

1. **Start all services with Docker Compose:**
   ```bash
   docker-compose up --build
   ```

   This will start:
   - PostgreSQL database (port 5432)
   - Auth service (port 3001)
   - Profile service (port 3002)
   - Chat service (port 3003)

2. **Run services individually (for development):**

   For each service (auth-service, profile-service, chat-service):
   ```bash
   cd backend/<service-name>
   npm install
   cp .env.example .env
   # Edit .env with your configuration
   npm run dev
   ```

### Frontend Setup

1. **Install dependencies:**
   ```bash
   cd frontend
   flutter pub get
   ```

2. **Configure backend URL:**
   Edit `lib/services/auth_service.dart` and update the `baseUrl` to point to your backend:
   ```dart
   final String baseUrl = 'http://YOUR_BACKEND_URL:3001';
   ```

3. **Configure RevenueCat:**
   - Sign up at [RevenueCat](https://www.revenuecat.com/)
   - Create a project and get your API keys
   - Edit `lib/services/subscription_service.dart` and replace `YOUR_REVENUECAT_API_KEY`

4. **Configure Sign in with Apple (iOS only):**
   - Add Sign in with Apple capability in Xcode
   - Configure your app's Bundle ID in Apple Developer Portal

5. **Configure Google Sign In:**
   - Create a project in [Google Cloud Console](https://console.cloud.google.com/)
   - Enable Google Sign-In API
   - Add OAuth 2.0 credentials
   - For iOS: Add your Bundle ID
   - For Android: Add your SHA-1 certificate fingerprint

6. **Run the app:**
   ```bash
   flutter run
   ```

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

1. **Change JWT_SECRET**: The default JWT secret is for development only. Use a strong, random secret in production.
2. **Apple/Google Token Verification**: Current implementation is stubbed. In production, verify Apple identity tokens and Google ID tokens server-side.
3. **HTTPS**: Use HTTPS in production for all API endpoints.
4. **Database**: Set strong passwords for PostgreSQL in production.

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