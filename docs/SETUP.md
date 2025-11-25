# NoBS Dating - Setup Guide

This guide will walk you through setting up the NoBS Dating application for development and production.

## Prerequisites

- Node.js 18+ and npm
- Docker and Docker Compose
- Flutter SDK 3.0+
- Xcode (for iOS development)
- Android Studio (for Android development)

## Step 1: Clone the Repository

```bash
git clone https://github.com/DasBluEyedDevil/NoBSDating.git
cd NoBSDating
```

## Step 2: Backend Setup

### 2.1 Create Environment File

Copy the example environment file and configure it:

```bash
cp .env.example .env
```

Edit `.env` and set the following variables:

```env
# PostgreSQL Configuration
POSTGRES_DB=nobsdating
POSTGRES_USER=postgres
POSTGRES_PASSWORD=YOUR_STRONG_PASSWORD_HERE

# Auth Service
AUTH_PORT=3001
JWT_SECRET=YOUR_STRONG_JWT_SECRET_HERE

# Other Services
PROFILE_PORT=3002
CHAT_PORT=3003
```

**Important Security Notes:**
- Generate a strong JWT secret: `openssl rand -base64 64`
- Use a strong database password
- Never commit your `.env` file to version control

### 2.2 Create Service Environment Files

For each service, create a `.env` file based on `.env.example`:

```bash
# Auth Service
cd backend/auth-service
cp .env.example .env
# Edit .env and update JWT_SECRET and DATABASE_URL

# Profile Service
cd ../profile-service
cp .env.example .env
# Edit .env and update DATABASE_URL

# Chat Service
cd ../chat-service
cp .env.example .env
# Edit .env and update DATABASE_URL
```

### 2.3 Start Backend Services

Return to the root directory and start all services:

```bash
cd ../..
./start-backend.sh
```

Or using Docker Compose directly:

```bash
docker-compose up --build
```

This will start:
- PostgreSQL database on port 5432
- Auth service on port 3001
- Profile service on port 3002
- Chat service on port 3003

### 2.4 Verify Backend Services

Check that all services are running:

```bash
curl http://localhost:3001/health
curl http://localhost:3002/health
curl http://localhost:3003/health
```

## Step 3: RevenueCat Setup

### 3.1 Create RevenueCat Account

1. Go to [RevenueCat](https://www.revenuecat.com/)
2. Sign up for a free account
3. Create a new project

### 3.2 Configure Products

1. In RevenueCat dashboard, go to "Products"
2. Create a new product (e.g., "Premium Monthly")
3. Configure pricing for App Store and Google Play

### 3.3 Create Entitlement

1. Go to "Entitlements"
2. Create a new entitlement named: **`premium_access`**
3. Link the entitlement to your products

### 3.4 Get API Keys

1. Go to "API Keys" in RevenueCat dashboard
2. Copy your API key for iOS
3. Copy your API key for Android (if different)

## Step 4: Apple Sign In Setup (iOS)

### 4.1 Apple Developer Portal

1. Log in to [Apple Developer Portal](https://developer.apple.com/)
2. Go to "Certificates, Identifiers & Profiles"
3. Create a new App ID (if needed)
4. Enable "Sign in with Apple" capability

### 4.2 Xcode Configuration

1. Open `frontend/ios/Runner.xcworkspace` in Xcode
2. Select the Runner target
3. Go to "Signing & Capabilities"
4. Add "Sign in with Apple" capability

## Step 5: Google Sign In Setup

### 5.1 Google Cloud Console

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project (or select existing)
3. Enable "Google Sign-In API"

### 5.2 Create OAuth 2.0 Credentials

**For iOS:**
1. Create OAuth 2.0 Client ID
2. Select "iOS" as application type
3. Add your Bundle ID (e.g., `com.yourcompany.nobsdating`)

**For Android:**
1. Create OAuth 2.0 Client ID
2. Select "Android" as application type
3. Add your package name
4. Get SHA-1 certificate fingerprint:
   ```bash
   keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
   ```

### 5.3 Download Configuration Files

**For iOS:**
- Download `GoogleService-Info.plist`
- Place in `frontend/ios/Runner/`

**For Android:**
- Download `google-services.json`
- Place in `frontend/android/app/`

## Step 6: Flutter Frontend Setup

### 6.1 Install Dependencies

```bash
cd frontend
flutter pub get
```

### 6.2 Configure Backend URLs

Edit `frontend/lib/config/app_config.dart` or use build-time variables:

```dart
// For iOS Simulator
static const String authServiceUrl = 'http://localhost:3001';

// For Android Emulator
static const String authServiceUrl = 'http://10.0.2.2:3001';

// For Real Device (use your computer's IP)
static const String authServiceUrl = 'http://192.168.1.XXX:3001';
```

Or set environment variables during build:

```bash
flutter run --dart-define=AUTH_SERVICE_URL=http://YOUR_IP:3001 --dart-define=REVENUECAT_API_KEY=YOUR_KEY
```

### 6.3 Update RevenueCat API Key

Set your RevenueCat API key using build-time variables:

```bash
flutter run --dart-define=REVENUECAT_API_KEY=YOUR_REVENUECAT_API_KEY
```

Or update the default value in `app_config.dart`:

```dart
static const String revenueCatApiKey = 'YOUR_ACTUAL_KEY';
```

## Step 7: Run the Application

### 7.1 iOS

```bash
cd frontend
flutter run -d ios
```

### 7.2 Android

```bash
cd frontend
flutter run -d android
```

### 7.3 Using Environment Variables

```bash
flutter run --dart-define=AUTH_SERVICE_URL=http://192.168.1.100:3001 \
            --dart-define=PROFILE_SERVICE_URL=http://192.168.1.100:3002 \
            --dart-define=CHAT_SERVICE_URL=http://192.168.1.100:3003 \
            --dart-define=REVENUECAT_API_KEY=YOUR_KEY
```

## Step 8: Testing

### 8.1 Test Authentication

1. Open the app
2. Tap "Sign in with Apple" (iOS) or "Sign in with Google"
3. Complete authentication flow
4. Verify you reach the main screen

### 8.2 Test Subscription

1. After signing in, you should see the paywall
2. Tap "Subscribe Now"
3. Complete the test purchase
4. Verify access to Discovery and Matches tabs

### 8.3 Test Backend APIs

```bash
# Test auth
curl -X POST http://localhost:3001/auth/google \
  -H "Content-Type: application/json" \
  -d '{"idToken":"test-token"}'

# Test profile
curl -X POST http://localhost:3002/profile \
  -H "Content-Type: application/json" \
  -d '{"userId":"test123","name":"John"}'

# Test chat
curl -X POST http://localhost:3003/matches \
  -H "Content-Type: application/json" \
  -d '{"userId1":"user1","userId2":"user2"}'
```

## Common Issues

### Issue: Flutter can't connect to backend

**Solution for iOS Simulator:**
Use `http://localhost:3001`

**Solution for Android Emulator:**
Use `http://10.0.2.2:3001`

**Solution for Real Device:**
- Find your computer's IP address: `ipconfig` (Windows) or `ifconfig` (Mac/Linux)
- Use `http://YOUR_IP:3001`
- Make sure device and computer are on same network
- Check firewall settings

### Issue: "JWT_SECRET must be set" error

**Solution:**
Create a `.env` file in the project root and set `JWT_SECRET=your-secret-here`

### Issue: PostgreSQL connection failed

**Solution:**
- Check if PostgreSQL container is running: `docker ps`
- Check database password in `.env` file
- Restart Docker Compose: `docker-compose down && docker-compose up`

### Issue: RevenueCat initialization fails

**Solution:**
- Verify your API key is correct
- Check you're using the right key for iOS/Android
- Ensure your app's Bundle ID matches RevenueCat configuration

## Production Deployment

### Backend

1. **Security:**
   - Generate strong JWT secret
   - Use strong database passwords
   - Enable HTTPS
   - Implement rate limiting
   - Add authentication middleware

2. **Hosting:**
   - Deploy to AWS ECS, Google Cloud Run, or similar
   - Use managed PostgreSQL (RDS, Cloud SQL)
   - Set up load balancing
   - Configure auto-scaling

3. **Monitoring:**
   - Add logging (CloudWatch, Stackdriver)
   - Set up alerts
   - Monitor API performance

### Frontend

1. **Build for Production:**
   ```bash
   # iOS
   flutter build ios --release \
     --dart-define=AUTH_SERVICE_URL=https://api.yourdomain.com/auth \
     --dart-define=REVENUECAT_API_KEY=prod_xxxx
   
   # Android
   flutter build apk --release \
     --dart-define=AUTH_SERVICE_URL=https://api.yourdomain.com/auth \
     --dart-define=REVENUECAT_API_KEY=prod_xxxx
   ```

2. **App Store / Play Store:**
   - Complete app store listings
   - Submit for review
   - Configure in-app purchases
   - Link to RevenueCat

3. **Testing:**
   - Test all authentication flows
   - Test subscription purchases
   - Test on real devices
   - Verify RevenueCat webhooks

## Support

For issues or questions:
- Check the [IMPLEMENTATION.md](IMPLEMENTATION.md) for technical details
- Review the [README.md](README.md) for API documentation
- File an issue on GitHub

## Security Checklist

Before deploying to production:

- [ ] Strong JWT secret configured
- [ ] Strong database password set
- [ ] HTTPS enabled on all services
- [ ] API rate limiting implemented
- [ ] Input validation added
- [ ] SQL injection protection verified
- [ ] RevenueCat webhooks configured
- [ ] Error messages don't leak sensitive info
- [ ] Secrets not committed to version control
- [ ] Authentication tokens properly verified
- [ ] CORS properly configured
- [ ] Security headers added
- [ ] Regular security audits scheduled
