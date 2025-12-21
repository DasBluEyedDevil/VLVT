# NoBS Dating (VLVT) - Project Summary

## Project Status: PRODUCTION READY (Beta)

This document provides a high-level summary of the NoBS Dating application implementation.

## What Was Built

A complete **dating application** featuring:

### Backend (Node.js/TypeScript/Express Microservices)

1. **Auth Service** (Port 3001)
   - Sign in with Apple (real token verification via apple-signin-auth)
   - Sign in with Google (real token verification via google-auth-library)
   - Email/Password authentication with bcrypt hashing
   - JWT access tokens + refresh tokens with database tracking
   - Token revocation support
   - Rate limiting (auth + general)

2. **Profile Service** (Port 3002)
   - Full CRUD for user profiles
   - Photo uploads with Sharp image processing
   - Cloudflare R2 storage for images (presigned URLs)
   - Location-based discovery using Haversine formula
   - Swipe/like/pass functionality with mutual match detection
   - Rate limiting per endpoint type

3. **Chat Service** (Port 3003)
   - Match management between users
   - Real-time messaging via Socket.io
   - Push notifications via Firebase Admin SDK
   - Typing indicators and read receipts
   - PostgreSQL persistence

4. **Database** (PostgreSQL)
   - Complete schema with migrations (6 migration files)
   - Tables: users, profiles, matches, messages, swipes, blocks, reports
   - Refresh token tracking with revocation
   - Deployed on Railway

### Frontend (Flutter)

1. **Authentication**
   - Sign in with Apple (iOS)
   - Sign in with Google (iOS & Android)
   - Email/Password registration and login
   - Email verification flow
   - Password reset flow
   - Secure JWT token storage (flutter_secure_storage)

2. **Main Interface** (3 Tabs)
   - **Discovery Tab**: Swipe through profiles, like/pass, distance display
   - **Matches Tab**: View matches, chat interface, real-time messaging
   - **Profile Tab**: Edit profile, manage photos, settings

3. **Subscription System**
   - RevenueCat SDK integration
   - Premium access entitlement checking
   - Paywall for non-premium features
   - Restore purchases functionality

4. **Additional Features**
   - Location services with permission handling
   - Push notifications
   - Block/report users (safety features)
   - Photo upload with camera/gallery picker

## Technical Stack

| Component | Technology |
|-----------|------------|
| Frontend Framework | Flutter 3.0+ |
| Frontend Language | Dart |
| Backend Runtime | Node.js 18+ |
| Backend Language | TypeScript 5.x |
| Backend Framework | Express 5.x |
| Database | PostgreSQL (Railway) |
| Image Storage | Cloudflare R2 |
| Real-time | Socket.io |
| Authentication | JWT + OAuth (Apple/Google) + Email/Password |
| Subscriptions | RevenueCat SDK |
| Push Notifications | Firebase Cloud Messaging |
| Error Tracking | Sentry |
| Deployment | Railway |

## Security Implementation

### Implemented
- Real OAuth token verification (Apple & Google)
- JWT with refresh token rotation
- Token revocation tracking in database
- bcrypt password hashing (cost factor 10)
- Rate limiting on all endpoints
- Helmet security headers
- CORS configuration
- Input validation with express-validator
- Parameterized SQL queries (SQL injection prevention)
- EXIF stripping from uploaded photos (privacy)
- Presigned URLs for image access (no public bucket)

### Test Data
- Seed data provides 20 test users with profiles, matches, and conversations
- Generate JWTs manually for test accounts (see `backend/seed-data/README.md`)

## Deployment

- **Backend**: Railway (3 microservices + PostgreSQL)
- **Images**: Cloudflare R2 with presigned URLs
- **Frontend**: App Store / Play Store (pending)

## Key Files

```
VLVT/
├── backend/
│   ├── auth-service/      # Authentication microservice
│   ├── profile-service/   # Profile & discovery microservice
│   ├── chat-service/      # Messaging microservice
│   └── migrations/        # Database migrations
├── frontend/
│   ├── lib/
│   │   ├── services/      # API clients, auth, location, etc.
│   │   ├── screens/       # UI screens
│   │   ├── models/        # Data models
│   │   └── widgets/       # Reusable components
│   └── android/ios/       # Platform-specific code
└── docs/                  # Documentation
```

## Environment Variables Required

### Auth Service
- `DATABASE_URL`, `JWT_SECRET`, `APPLE_*`, `GOOGLE_*`

### Profile Service
- `DATABASE_URL`, `JWT_SECRET`, `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET_NAME`

### Chat Service
- `DATABASE_URL`, `JWT_SECRET`, `FIREBASE_*`

---

**Last Updated**: December 2025
**Status**: Beta testing on Android
