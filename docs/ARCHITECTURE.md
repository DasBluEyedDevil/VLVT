# NoBS Dating - Architecture Overview

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Flutter App                              │
│  ┌──────────────┬──────────────┬──────────────┬──────────────┐  │
│  │    Auth      │  Discovery   │   Matches    │   Profile    │  │
│  │   Screen     │   Screen     │   Screen     │   Screen     │  │
│  └──────────────┴──────────────┴──────────────┴──────────────┘  │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              State Management (Provider)                  │   │
│  │  ┌──────────────────┐    ┌──────────────────────────┐   │   │
│  │  │  AuthService     │    │  SubscriptionService     │   │   │
│  │  │  - Sign in       │    │  - RevenueCat SDK       │   │   │
│  │  │  - JWT tokens    │    │  - Premium check        │   │   │
│  │  └──────────────────┘    └──────────────────────────┘   │   │
│  └──────────────────────────────────────────────────────────┘   │
└───────────────────────┬─────────────────────────┬───────────────┘
                        │                         │
                        │ HTTPS/REST API         │ RevenueCat
                        │                         │ Cloud
                        ▼                         ▼
┌──────────────────────────────────────────────────────────────────┐
│                     Backend Services (Docker)                     │
│                                                                    │
│  ┌──────────────────┐  ┌──────────────────┐  ┌────────────────┐ │
│  │  Auth Service    │  │ Profile Service  │  │  Chat Service  │ │
│  │   Port: 3001     │  │   Port: 3002     │  │   Port: 3003   │ │
│  │                  │  │                  │  │                │ │
│  │ • Apple Sign In  │  │ • CRUD Profiles  │  │ • Matches      │ │
│  │ • Google Sign In │  │ • Discovery      │  │ • Messages     │ │
│  │ • JWT Generation │  │                  │  │                │ │
│  └────────┬─────────┘  └────────┬─────────┘  └────────┬───────┘ │
│           │                     │                      │         │
│           └─────────────────────┴──────────────────────┘         │
│                                 │                                │
│                                 ▼                                │
│                    ┌─────────────────────────┐                   │
│                    │   PostgreSQL Database   │                   │
│                    │      Port: 5432         │                   │
│                    │                         │                   │
│                    │ • users                 │                   │
│                    │ • profiles              │                   │
│                    │ • matches               │                   │
│                    │ • messages              │                   │
│                    └─────────────────────────┘                   │
└──────────────────────────────────────────────────────────────────┘
```

## Authentication Flow

```
┌──────────┐                                    ┌──────────────┐
│  User    │                                    │ Apple/Google │
└────┬─────┘                                    └──────┬───────┘
     │                                                 │
     │ 1. Tap "Sign in"                               │
     ├─────────────────────────────────────────────►  │
     │                                                 │
     │ 2. Native Auth Flow                            │
     │ ◄───────────────────────────────────────────── │
     │                                                 │
     │ 3. Identity/ID Token                           │
     │ ◄───────────────────────────────────────────── │
     │                                                 │
     ▼                                                 
┌─────────────────┐
│  Flutter App    │
└────┬────────────┘
     │ 4. Send token to backend
     │
     ▼
┌─────────────────┐
│  Auth Service   │
│   (Port 3001)   │
└────┬────────────┘
     │ 5. Generate JWT
     │
     ▼
┌─────────────────┐
│  Flutter App    │
└────┬────────────┘
     │ 6. Store JWT securely
     │
     ▼
┌─────────────────┐
│  Authenticated  │
└─────────────────┘
```

## Subscription Gating Flow

```
┌──────────────────┐
│  User Signs In   │
└────────┬─────────┘
         │
         ▼
┌─────────────────────────────┐
│ RevenueCat: Check           │
│ "premium_access" entitlement│
└────────┬────────────────────┘
         │
         │
    ┌────┴────┐
    │         │
    ▼         ▼
┌─────┐   ┌──────┐
│ Yes │   │  No  │
└──┬──┘   └───┬──┘
   │          │
   │          ▼
   │     ┌─────────────────┐
   │     │  Show Paywall   │
   │     │  • Block tabs   │
   │     │  • Show benefits│
   │     └────────┬────────┘
   │              │
   │              │ User subscribes
   │              ▼
   │     ┌─────────────────┐
   │     │ Purchase via    │
   │     │ RevenueCat SDK  │
   │     └────────┬────────┘
   │              │
   │              │ Entitlement updated
   │              ▼
   │     ┌─────────────────┐
   │     │ Unlock features │
   │     └────────┬────────┘
   │              │
   └──────────────┘
                  │
                  ▼
         ┌──────────────────┐
         │  3-Tab Interface │
         │  • Discovery     │
         │  • Matches       │
         │  • Profile       │
         └──────────────────┘
```

## Technology Stack

### Frontend
- **Framework**: Flutter 3.0+
- **Language**: Dart
- **State Management**: Provider
- **Authentication**: 
  - sign_in_with_apple: ^5.0.0
  - google_sign_in: ^6.1.5
- **Subscriptions**: purchases_flutter: ^6.0.0 (RevenueCat)
- **Storage**: flutter_secure_storage: ^9.0.0
- **HTTP**: http: ^1.1.0

### Backend
- **Runtime**: Node.js 18+
- **Language**: TypeScript 5.7.2
- **Framework**: Express 4.21.1
- **Database**: PostgreSQL 15
- **Authentication**: jsonwebtoken: ^9.0.2
- **Containerization**: Docker & Docker Compose

### Infrastructure
- **Database**: PostgreSQL 15 Alpine (Docker)
- **Container Orchestration**: Docker Compose
- **Environment Management**: dotenv

## Data Models

### User
```typescript
interface User {
  id: string;
  provider: 'apple' | 'google';
  email: string;
  created_at: Date;
  updated_at: Date;
}
```

### Profile
```typescript
interface Profile {
  userId: string;
  name?: string;
  age?: number;
  bio?: string;
  photos?: string[];
  interests?: string[];
}
```

### Match
```typescript
interface Match {
  id: string;
  userId1: string;
  userId2: string;
  createdAt: Date;
}
```

### Message
```typescript
interface Message {
  id: string;
  matchId: string;
  senderId: string;
  text: string;
  timestamp: Date;
}
```

## API Endpoints

### Auth Service (3001)
- `GET /health` - Health check
- `POST /auth/apple` - Sign in with Apple
- `POST /auth/google` - Sign in with Google
- `POST /auth/verify` - Verify JWT token

### Profile Service (3002)
- `GET /health` - Health check
- `POST /profile` - Create profile
- `GET /profile/:userId` - Get profile
- `PUT /profile/:userId` - Update profile
- `DELETE /profile/:userId` - Delete profile
- `GET /profiles/discover` - Get discovery profiles

### Chat Service (3003)
- `GET /health` - Health check
- `GET /matches/:userId` - Get user matches
- `POST /matches` - Create match
- `GET /messages/:matchId` - Get messages
- `POST /messages` - Send message

## Security Layers

### Layer 1: Authentication
- Passwordless sign-in (Apple/Google)
- JWT token-based session management
- Secure token storage (flutter_secure_storage)

### Layer 2: Authorization
- JWT verification on protected endpoints
- Subscription status check via RevenueCat

### Layer 3: Data Protection
- HTTPS for all communications
- Environment-based configuration
- No hardcoded secrets

### Layer 4: Application Security
- Input validation (to be implemented)
- Rate limiting (to be implemented)
- SQL injection prevention (parameterized queries needed)

## Deployment Considerations

### Development
```bash
# Backend
docker-compose up

# Frontend
flutter run --dart-define=AUTH_SERVICE_URL=http://localhost:3001
```

### Production
- Deploy backend services to cloud (AWS ECS, GCP Cloud Run, etc.)
- Use managed PostgreSQL (RDS, Cloud SQL)
- Configure load balancer
- Enable HTTPS/TLS
- Set up monitoring and logging
- Implement CI/CD pipeline
- Add CDN for static assets

## Scalability

### Current Architecture
- Microservices: ✅ (3 independent services)
- Stateless services: ✅ (JWT-based auth)
- Containerized: ✅ (Docker)
- Database: ⚠️ (Single PostgreSQL instance)

### For Scale
- Add load balancers
- Implement database replication
- Add caching layer (Redis)
- Implement message queue (RabbitMQ/SQS)
- Add CDN
- Implement horizontal auto-scaling
- Add database sharding if needed

## Monitoring & Observability

### To Implement
- Application logging (Winston, Bunyan)
- Metrics collection (Prometheus)
- Tracing (Jaeger, OpenTelemetry)
- Error tracking (Sentry)
- Performance monitoring (New Relic, DataDog)
- Health checks on all services
- Database query monitoring
- API endpoint analytics

## Future Enhancements

### Backend
- [ ] Real-time chat (WebSockets)
- [ ] Push notifications
- [ ] Image upload/storage (S3, Cloud Storage)
- [ ] Advanced matching algorithm
- [ ] Report/block users
- [ ] Content moderation
- [ ] Analytics service
- [ ] Admin panel

### Frontend
- [ ] Swipe animations
- [ ] Photo gallery
- [ ] Video profiles
- [ ] Voice/video calls
- [ ] In-app notifications
- [ ] Advanced filters
- [ ] Profile verification
- [ ] Activity feed

### Infrastructure
- [ ] CI/CD pipeline
- [ ] Blue-green deployments
- [ ] Automated testing
- [ ] Security scanning
- [ ] Performance testing
- [ ] Backup automation
- [ ] Disaster recovery

---

For more details, see:
- [README.md](README.md) - Overview and quick start
- [SETUP.md](SETUP.md) - Detailed setup instructions
- [IMPLEMENTATION.md](IMPLEMENTATION.md) - Technical details
- [SECURITY.md](SECURITY.md) - Security considerations
