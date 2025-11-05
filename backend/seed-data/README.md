# Test Database Seeding

This directory contains scripts and data for populating the NoBS Dating database with realistic test users for comprehensive testing.

## Overview

The seeding script creates:
- **20 test users** with diverse personas
- **20 detailed profiles** with realistic bios and interests
- **20 matches** at various relationship stages
- **35+ messages** forming realistic conversations

All test data is prefixed with `test_` or `google_test` for easy identification and cleanup.

## Quick Start

### 1. Seed the Database

```bash
cd backend/seed-data

# Make sure pg module is available
npm install pg

# Seed with default connection (localhost)
node seed.js

# Or specify your database URL
DATABASE_URL="postgresql://user:pass@host:5432/dbname" node seed.js

# Clean existing test data first, then seed
node seed.js --clean

# Only clean test data (useful for reset)
node seed.js --clean-only
```

### 2. Using SQL Script Directly

Alternatively, you can run the SQL script directly:

```bash
psql $DATABASE_URL -f seed.sql
```

## Test Users

All test users follow the pattern `google_test###` (e.g., `google_test001`):

### Featured Test Personas

| ID | Name | Age | Personality | Interests |
|----|------|-----|-------------|-----------|
| google_test001 | Alex Chen | 28 | Software engineer, foodie, adventurer | Cooking, Tech, Travel, Photography |
| google_test002 | Jordan Rivera | 25 | Yoga instructor, positive vibes | Yoga, Fitness, Coffee, Nature |
| google_test003 | Sam Patel | 31 | Marketing strategist, music lover | Music, Concerts, Vinyl, Comedy |
| google_test004 | Taylor Kim | 27 | Graphic designer, art enthusiast | Art, Design, Museums |
| google_test005 | Morgan Santos | 29 | Rock climbing addict | Climbing, Outdoors, Fitness, Travel |
| google_test006 | Casey Nguyen | 26 | Teacher, board game fan | Board Games, Teaching, Comedy |
| google_test007 | Riley Anderson | 30 | Data scientist, craft beer lover | Science, Beer, Books, Philosophy |
| google_test008 | Avery Williams | 24 | Photographer, dog lover | Photography, Dogs, Nature, Art |
| google_test009 | Drew Martinez | 32 | Entrepreneur, go-getter | Entrepreneurship, Travel, Fitness |
| google_test010 | Charlie Lee | 28 | Bookworm, aspiring novelist | Reading, Writing, Coffee, Art |
| google_test011 | Jamie Brown | 26 | Personal trainer | Fitness, Health, Cooking, Running |
| google_test012 | Quinn Davis | 29 | Architect | Architecture, Design, Travel |
| google_test013 | Reese Garcia | 27 | Marine biologist | Scuba Diving, Ocean, Science |
| google_test014 | Skylar Wilson | 25 | Pastry chef | Baking, Cooking, Food, Coffee |
| google_test015 | Blake Moore | 30 | Lawyer, comedian | Comedy, Improv, Debate, Theater |
| google_test016 | Phoenix Taylor | 28 | DJ, festival enthusiast | Music, DJing, Festivals, Dancing |
| google_test017 | Sage Jackson | 26 | Veterinarian, plant parent | Animals, Plants, Nature, Hiking |
| google_test018 | Dakota White | 31 | Financial advisor, travel hacker | Travel, Finance, Wine |
| google_test019 | River Harris | 24 | Video game developer | Gaming, Anime, Technology, Coding |
| google_test020 | Ocean Clark | 27 | Environmental scientist | Environment, Sustainability, Vegan |

## Logging In as Test Users

### Option 1: Test Login Endpoint (Recommended)

The auth service includes a development-only test login endpoint:

```bash
# Login as Alex Chen
curl -X POST http://localhost:3001/auth/test-login \
  -H "Content-Type: application/json" \
  -d '{"userId": "google_test001"}'

# Response:
{
  "success": true,
  "token": "eyJhbGc...",
  "userId": "google_test001",
  "provider": "google",
  "email": "alex.chen@test.com"
}
```

Use the returned `token` in subsequent API requests:

```bash
curl -X GET http://localhost:3002/profile/google_test001 \
  -H "Authorization: Bearer eyJhbGc..."
```

### Option 2: Frontend Test Login UI

For easier testing in the Flutter app, we've created a test user selector screen (see `frontend/lib/screens/test_login_screen.dart`). This provides:

- Visual list of all 20 test personas
- One-tap login
- Profile previews
- Easy switching between users

To enable it, modify `frontend/lib/screens/auth_screen.dart` to show a "Test Users" button in development mode.

### Option 3: Manual JWT Generation

Generate tokens manually using your JWT secret:

```javascript
const jwt = require('jsonwebtoken');
const token = jwt.sign(
  {
    userId: 'google_test001',
    provider: 'google',
    email: 'alex.chen@test.com'
  },
  'your_jwt_secret',
  { expiresIn: '7d' }
);
```

## Test Data Scenarios

### Active Conversations (Recent Messages)

- **Alex & Jordan** (test_match_001): Flirty, planning a date
- **Alex & Morgan** (test_match_002): Outdoor adventure plans
- **Sam & Phoenix** (test_match_007): Music bonding
- **Jordan & Casey** (test_match_004): Fun, lighthearted chat

### New Matches (No Messages Yet)

- **Blake & Ocean** (test_match_016): Just matched 2 hours ago
- **Phoenix & River** (test_match_017): Just matched 4 hours ago
- **Sage & Ocean** (test_match_018): Just matched 6 hours ago

### Older Matches (Inactive)

- **Riley & River** (test_match_011): Matched 10 days ago
- **Avery & Sage** (test_match_012): Matched 8 days ago
- **Drew & Dakota** (test_match_013): Matched 9 days ago

### No Matches

Several users have no matches, perfect for testing the discovery flow:
- google_test020 (Ocean) - has 2 matches but good for more
- Any newly created test users

## Testing Scenarios

### 1. New User Onboarding
Login as a user without a complete profile (create one manually without name/age) to test the profile setup flow.

### 2. Discovery Flow
- Login as google_test020
- Test profile browsing
- Test filters (age, distance, interests)
- Test like/pass actions
- Test profile loop prevention

### 3. Matching
- Login as google_test001
- Like google_test020
- Switch to google_test020
- See the match appear

### 4. Chat Testing
- Login as google_test001
- View existing conversations with Jordan, Morgan, Charlie
- Test message sending
- Test real-time polling (open on two devices)
- Test message retry

### 5. Subscription Flow
- All test users start without premium
- Test demo mode limits (5 likes, 10 messages)
- Test upgrade prompts
- Test paywall flow

### 6. Safety Features
- Test blocking (login as two different users)
- Test reporting
- Test unmatch
- View safety settings

## Cleanup

### Remove All Test Data

```bash
# Using the seed script
node seed.js --clean-only

# Or manually via psql
psql $DATABASE_URL -c "DELETE FROM messages WHERE match_id LIKE 'test_%'"
psql $DATABASE_URL -c "DELETE FROM matches WHERE id LIKE 'test_%'"
psql $DATABASE_URL -c "DELETE FROM blocks WHERE user_id LIKE 'google_test%'"
psql $DATABASE_URL -c "DELETE FROM reports WHERE reporter_id LIKE 'google_test%'"
psql $DATABASE_URL -c "DELETE FROM profiles WHERE user_id LIKE 'google_test%'"
psql $DATABASE_URL -c "DELETE FROM users WHERE id LIKE 'google_test%'"
```

### Remove Specific User

```bash
USER_ID="google_test001"
psql $DATABASE_URL -c "DELETE FROM messages WHERE sender_id = '$USER_ID'"
psql $DATABASE_URL -c "DELETE FROM matches WHERE user_id_1 = '$USER_ID' OR user_id_2 = '$USER_ID'"
psql $DATABASE_URL -c "DELETE FROM blocks WHERE user_id = '$USER_ID' OR blocked_user_id = '$USER_ID'"
psql $DATABASE_URL -c "DELETE FROM reports WHERE reporter_id = '$USER_ID' OR reported_user_id = '$USER_ID'"
psql $DATABASE_URL -c "DELETE FROM profiles WHERE user_id = '$USER_ID'"
psql $DATABASE_URL -c "DELETE FROM users WHERE id = '$USER_ID'"
```

## Environment Variables

The seeding script uses these environment variables:

```bash
# Database connection
DATABASE_URL=postgresql://user:password@host:5432/database

# For auth service test login endpoint
JWT_SECRET=your_secret_key
NODE_ENV=development  # Test login only works when NOT production
```

## File Structure

```
backend/seed-data/
├── README.md           # This file
├── seed.sql           # SQL script with test data
├── seed.js            # Node.js seeding script
└── package.json       # Dependencies (pg)
```

## Troubleshooting

### "relation does not exist" error

Make sure all migrations have been run:

```bash
cd backend/migrations
./run_migration.sh
```

### "connection refused" error

Check that PostgreSQL is running and DATABASE_URL is correct:

```bash
psql $DATABASE_URL -c "SELECT 1"
```

### Test login endpoint not found

Make sure NODE_ENV is NOT set to "production":

```bash
unset NODE_ENV
# or
export NODE_ENV=development
```

### JWT token invalid

Verify your JWT_SECRET matches between auth service and token generation.

## Adding More Test Data

To add additional test users:

1. Add user to the `users` INSERT statement in `seed.sql`
2. Add profile to the `profiles` INSERT statement
3. Optionally add matches and messages
4. Follow the naming convention: `google_test###` for users, `test_###` for other IDs
5. Re-run the seed script

## Production Warning

⚠️ **IMPORTANT**: The test login endpoint is DISABLED in production environments. Never use these test accounts or the test login endpoint in production!

The test login endpoint only works when `NODE_ENV !== 'production'`.

## Support

For issues or questions:
- Check the main README.md
- Review the IMPLEMENTATION.md docs
- Check that all services are running (auth, profile, chat)
- Verify database migrations are complete
