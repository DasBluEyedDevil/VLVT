# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

VLVT is a dating app built with a Flutter frontend and Node.js/TypeScript microservices backend. The app uses RevenueCat for subscriptions, Firebase for analytics/crashlytics/push notifications, and PostgreSQL for data persistence.

## Build & Development Commands

### Full Stack (Docker)
```bash
cp .env.example .env               # Copy and configure environment
docker-compose up --build          # Start Postgres + all services
```

### Frontend (Flutter)
```bash
cd frontend
flutter pub get                    # Install dependencies
flutter run                        # Run in debug mode (uses localhost backend)
flutter run --dart-define=USE_PROD_URLS=true  # Run against production backend
flutter analyze                    # Static analysis
flutter test                       # Run all tests
flutter test test/widgets/specific_test.dart  # Run single test file
flutter build ios                  # iOS release build
flutter build apk --release        # Android release build
```

### Backend Services (Node.js/TypeScript)
Each service (auth-service, profile-service, chat-service) in `backend/`:
```bash
npm install          # Install dependencies
npm run dev          # Development with ts-node
npm run build        # Compile TypeScript
npm start            # Run compiled code
npm test             # Run Jest tests
npm run test:watch   # Watch mode
npm run test:coverage
npm test -- --testPathPattern="specific.test.ts"  # Run single test
```

### Database
```bash
# Run migrations (requires DATABASE_URL environment variable)
cd backend/migrations
npm run migrate

# Seed test data (requires Postgres running)
cd backend/seed-data
npm run seed         # Add test users
npm run seed:fresh   # Clean and re-seed
npm run clean        # Remove test data
```

## Architecture

### Microservices Backend
- **auth-service** (port 3001): JWT authentication, Apple/Google Sign-In, password auth, email verification
- **profile-service** (port 3002): User profiles, discovery, photo management (Sharp for processing)
- **chat-service** (port 3003): Matches, messaging, real-time via Socket.io, push notifications via Firebase Admin

All services use Express, PostgreSQL (pg), Winston logging, Helmet security, rate limiting, and deploy to Railway.

### Frontend State Management
Uses Provider pattern with ChangeNotifierProxyProvider for dependent services:
- `AuthService` - Authentication state, JWT tokens (stored in flutter_secure_storage)
- `SubscriptionService` - RevenueCat entitlements
- `ProfileApiService`, `ChatApiService` - Depend on AuthService for auth tokens
- `SocketService` - Real-time messaging
- `LocationService` - GPS with permission_handler
- `ThemeService` - Light/dark mode

### Key Frontend Structure
- `lib/main.dart` - App entry, provider setup, auth wrapper
- `lib/screens/` - UI screens (auth, discovery, matches, chat, profile, paywall)
- `lib/services/` - Business logic and API clients
- `lib/models/` - Data models (Profile, Match, Message)
- `lib/config/app_config.dart` - Service URLs, API keys (via --dart-define)
- `lib/widgets/` - Reusable components

### Database Schema
PostgreSQL with 6 migration files:
1. users & profiles
2. matches & messages
3. blocks & reports (safety)
4. realtime features (typing indicators, read receipts)
5. subscriptions
6. auth credentials (password auth)

### URL Configuration
Frontend auto-detects environment:
- Debug mode: localhost (10.0.2.2 for Android emulator)
- Release mode: Railway production URLs
- Override: `--dart-define=USE_PROD_URLS=true`

### Test Users
Test users: google_test001 through google_test020 (see docs/TESTING.md). Generate JWTs manually using `backend/seed-data/README.md` and use them for API testing.

## Deployment

Railway deployment for backend services:
```bash
railway login
railway link
railway up
```

Required environment variables per service:
- `DATABASE_URL` - PostgreSQL connection string
- `JWT_SECRET` - Auth service only
- `NODE_ENV=production`
- `PORT` - 3001/3002/3003

## Key Dependencies
- **Flutter**: provider, http, firebase_*, purchases_flutter (RevenueCat), socket_io_client, geolocator, cached_network_image
- **Backend**: express, pg, jsonwebtoken, socket.io, firebase-admin, sharp, bcrypt, winston

## Coding Conventions

### TypeScript (Backend)
- 2-space indentation, single quotes, async/await pattern
- PascalCase for classes/types, camelCase for functions/variables
- New modules go under `src/` (e.g., `utils/logger.ts`, `middleware/auth.ts`)
- Reuse existing validation middleware and rate-limit patterns when adding routes

### Flutter (Frontend)
- Files use `snake_case.dart`, widgets/classes use PascalCase
- Follow `analysis_options.yaml` (flutter_lints)
- Use shared theme components from `lib/theme/` and `lib/widgets/`
- Tokens stored via flutter_secure_storage

### Git Commits
Use Conventional Commits with scope: `feat(vlvt):`, `fix(auth-service):`, `refactor(frontend):`

## Testing Notes
- **Backend**: Jest suites in `backend/*/tests/`; start Postgres first; include unhappy-path tests
- **Frontend**: Widget tests in `frontend/test/`; use mocked services; keep "Test Users (Dev Only)" login working
- **Test users**: google_test001 through google_test020 available via seed data
