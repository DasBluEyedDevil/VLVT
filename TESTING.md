# NoBS Dating Testing Guide

This guide explains how to test the NoBSDating app using the pre-configured test database with 20 realistic personas.

## Quick Start

### 1. Seed the Database

```bash
cd backend/seed-data
npm install
npm run seed
```

This creates 20 test users with profiles, matches, and conversations.

### 2. Start the Backend Services

```bash
# Terminal 1: Auth Service
cd backend/auth-service
npm start

# Terminal 2: Profile Service
cd backend/profile-service
npm start

# Terminal 3: Chat Service
cd backend/chat-service
npm start
```

### 3. Run the Flutter App

```bash
cd frontend
flutter pub get
flutter run
```

### 4. Login as a Test User

On the auth screen, tap the **"Test Users (Dev Only)"** button (visible in debug mode only).

Select any test user to login instantly without OAuth.

---

## Test User Personas

### 👨‍💻 Alex Chen (google_test001)
- **Age:** 28
- **Bio:** Software engineer, foodie, adventurer
- **Interests:** Cooking, Tech, Travel, Photography
- **Matches:** Has 3 active conversations
- **Best for testing:** Chat functionality, active conversations

### 🧘 Jordan Rivera (google_test002)
- **Age:** 25
- **Bio:** Yoga instructor, positive vibes
- **Interests:** Yoga, Fitness, Coffee, Nature
- **Matches:** Has 2 active conversations
- **Best for testing:** New matches, chat flow

### 🎵 Sam Patel (google_test003)
- **Age:** 31
- **Bio:** Marketing strategist, music lover
- **Interests:** Music, Concerts, Vinyl, Comedy
- **Matches:** Has 2 matches
- **Best for testing:** Match discovery, interests filtering

### 🎨 Taylor Kim (google_test004)
- **Age:** 27
- **Bio:** Graphic designer, art enthusiast
- **Interests:** Art, Design, Museums
- **Matches:** Has 2 matches
- **Best for testing:** Profile display, interests

### 🧗 Morgan Santos (google_test005)
- **Age:** 29
- **Bio:** Rock climbing addict
- **Interests:** Climbing, Outdoors, Fitness, Travel
- **Matches:** Has 1 match
- **Best for testing:** Active conversation, outdoor enthusiast profile

### 🎲 Casey Nguyen (google_test006)
- **Age:** 26
- **Bio:** Teacher, board game fan
- **Interests:** Board Games, Teaching, Comedy
- **Matches:** Has 2 matches
- **Best for testing:** Fun conversations

### 📊 Riley Anderson (google_test007)
- **Age:** 30
- **Bio:** Data scientist, craft beer lover
- **Interests:** Science, Beer, Books, Philosophy
- **Matches:** Has 2 matches
- **Best for testing:** Intellectual conversations

### 📷 Avery Williams (google_test008)
- **Age:** 24
- **Bio:** Photographer, dog lover
- **Interests:** Photography, Dogs, Nature, Art
- **Matches:** Has 2 matches
- **Best for testing:** Animal lover profile

### 💼 Drew Martinez (google_test009)
- **Age:** 32
- **Bio:** Entrepreneur, go-getter
- **Interests:** Entrepreneurship, Travel, Fitness
- **Matches:** Has 1 match
- **Best for testing:** Ambitious personality

### 📚 Charlie Lee (google_test010)
- **Age:** 28
- **Bio:** Bookworm, aspiring novelist
- **Interests:** Reading, Writing, Coffee, Art
- **Matches:** Has 2 matches
- **Best for testing:** Literary conversations

...and 10 more diverse personas! See `backend/seed-data/README.md` for the full list.

---

## Testing Scenarios

### 🎯 New User Onboarding
1. Login as any test user
2. On first login, you'll be prompted to complete profile setup
3. Test form validation (age must be 18+, name required)
4. Test interest chip management
5. Verify profile saves correctly

### 💜 Discovery Flow
**Recommended user:** Ocean Clark (google_test020) - fewer matches, good for discovery

1. Navigate to Discovery tab
2. View profile cards
3. Test "Pass" button - profile moves to next
4. Test "Like" button - creates match
5. Test profile counter in AppBar
6. Test undo button (appears for 3 seconds after action)
7. Test filters (tap filter icon in AppBar)
   - Adjust age range
   - Change distance
   - Select interests
8. Test reaching end of profiles
9. Verify no duplicate profiles appear (24h history tracking)

### 💑 Matching
1. Login as google_test020 (Ocean)
2. Go to Discovery tab
3. Like google_test001 (Alex)
4. Switch accounts to Alex
5. Check if match appears in Matches tab
6. Verify match notification/badge

### 💬 Chat & Messaging
**Recommended user:** Alex Chen (google_test001) - has active conversations

1. Navigate to Matches tab
2. View existing matches
3. Tap on Jordan Rivera match
4. View conversation history
5. Test sending messages
6. Test character counter (500 char limit)
7. Test typing indicator
8. Test message retry (turn off wifi, send message, turn wifi back on, retry)
9. Test pull-to-refresh
10. Open chat on two devices/simulators to test real-time polling

### 🔔 Unread Messages
1. Login as Alex (google_test001)
2. Have a friend login as Jordan (google_test002)
3. Jordan sends message
4. Check if unread badge appears on Alex's match item
5. Alex opens chat
6. Verify badge disappears

### 💎 Subscription Flow (Demo Mode)
**All test users start without premium**

1. Login as any test user
2. See upgrade banner at top showing "5 likes left"
3. Navigate to Discovery
4. Like 5 profiles
5. On 6th like attempt, see premium gate dialog
6. Tap "Continue with Premium" to view paywall
7. View pricing, features, free trial info
8. Tap "Continue with Limited Access" to return
9. Repeat for messages (10 message limit)

### 🔐 Safety Features

#### Blocking:
1. Login as Alex (google_test001)
2. Open chat with Jordan (google_test002)
3. Tap three-dot menu in AppBar
4. Select "Block User"
5. Confirm action
6. Verify Jordan disappears from matches
7. Verify Jordan doesn't appear in discovery
8. Login as Jordan
9. Verify Alex doesn't appear anywhere
10. Go to Profile > Safety Settings > Blocked Users
11. Unblock Alex

#### Reporting:
1. Login as any user
2. Open chat or view profile in discovery
3. Tap flag icon or open action menu
4. Select "Report User"
5. Choose reason (Inappropriate, Harassment, Spam, etc.)
6. Add details (optional)
7. Submit report
8. Verify success message

#### Unmatching:
1. Go to Matches tab
2. Swipe left on any match item
3. Tap "Unmatch"
4. Confirm action
5. Verify match removed
6. Check undo snackbar (4 second window)

### 🔍 Search & Sort
1. Login as Alex (google_test001) - has multiple matches
2. Go to Matches tab
3. Tap search icon in AppBar
4. Type "Jordan" to filter matches
5. Clear search
6. Tap sort icon
7. Try different sort options:
   - Recent Activity (default)
   - Newest Matches
   - Name (A-Z)

### 📝 Profile Editing
1. Login as any test user
2. Navigate to Profile tab
3. Tap "Edit Profile" button
4. Modify name, age, bio, interests
5. Test validation:
   - Name required (min 2 chars)
   - Age required (18-120)
   - Bio optional (max 500 chars)
6. Add/remove interests
7. Save profile
8. Verify changes appear immediately

### 🌐 Offline Mode
1. Open app while connected
2. Browse profiles, matches, chat
3. Turn off wifi/cellular
4. See offline banner at top
5. Try to perform actions
6. Verify helpful error messages
7. Turn connection back on
8. Tap "Retry" on offline banner
9. Verify data loads

### 🎨 UI/UX Polish
1. Check loading states use skeletons (not spinners)
2. Verify smooth animations on:
   - Card transitions in discovery
   - Button presses (scale effect)
   - Tab switches
   - Screen transitions
3. Test pull-to-refresh across screens
4. Check empty states have illustrations and CTAs
5. Verify error messages are user-friendly
6. Test confirmation dialogs for destructive actions

---

## Performance Testing

### Match Screen Performance
1. Login as Alex (google_test001)
2. Open DevTools network tab
3. Navigate to Matches tab
4. Count API calls on first load (should be ~3 batched calls)
5. Navigate away and back
6. Verify subsequent loads use cache (0 API calls within 5 min)

### Discovery Caching
1. Login and browse 10 profiles in discovery
2. Switch to Matches tab
3. Switch back to Discovery
4. Verify you return to the same position (state persistence)
5. Close app completely
6. Reopen app
7. Go to Discovery
8. Verify you don't see the same profiles again (24h history)

### Chat Polling
1. Open chat screen
2. Watch network tab
3. Verify polling requests every 4 seconds
4. Background the app
5. Verify polling stops (check console logs)
6. Foreground the app
7. Verify polling resumes

---

## API Testing

### Test Login Endpoint

**Endpoint:** `POST http://localhost:3001/auth/test-login`

```bash
curl -X POST http://localhost:3001/auth/test-login \
  -H "Content-Type: application/json" \
  -d '{"userId": "google_test001"}'
```

**Response:**
```json
{
  "success": true,
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "userId": "google_test001",
  "provider": "google",
  "email": "alex.chen@test.com"
}
```

Use the token for authenticated requests:

```bash
TOKEN="eyJhbGciOiJIUzI..."

# Get profile
curl http://localhost:3002/profile/google_test001 \
  -H "Authorization: Bearer $TOKEN"

# Get matches
curl http://localhost:3003/matches/google_test001 \
  -H "Authorization: Bearer $TOKEN"

# Get messages
curl http://localhost:3003/messages/test_match_001 \
  -H "Authorization: Bearer $TOKEN"
```

---

## Database Management

### View Current Test Data

```bash
psql $DATABASE_URL -c "SELECT COUNT(*) FROM users WHERE id LIKE 'google_test%'"
psql $DATABASE_URL -c "SELECT COUNT(*) FROM profiles WHERE user_id LIKE 'google_test%'"
psql $DATABASE_URL -c "SELECT COUNT(*) FROM matches WHERE id LIKE 'test_%'"
psql $DATABASE_URL -c "SELECT COUNT(*) FROM messages WHERE match_id LIKE 'test_%'"
```

### Clean Test Data

```bash
cd backend/seed-data
npm run clean
```

Or use the script with clean flag:

```bash
npm run seed:clean
```

### Reseed Database

```bash
cd backend/seed-data
npm run clean  # Remove old data
npm run seed   # Add fresh data
```

---

## Multi-Device Testing

### Simulating Two Users Chatting

**Device 1 (iOS Simulator):**
1. Run: `flutter run`
2. Login as Alex (google_test001)
3. Open chat with Jordan

**Device 2 (Android Emulator):**
1. Run: `flutter run -d <android-device-id>`
2. Login as Jordan (google_test002)
3. Open chat with Alex

Now send messages back and forth. You should see:
- Real-time message updates (4s polling)
- Unread badges updating
- Typing indicators (local only currently)
- Message status updates

---

## Troubleshooting

### "Test Users" button not showing
- Make sure you're running in debug mode (`flutter run`)
- Check that `kDebugMode` is true
- Button is hidden in production builds

### Test login endpoint returns 404
- Verify `NODE_ENV` is NOT set to "production"
- Restart auth service
- Check console logs for "Test login endpoint enabled" message

### No test data in database
- Run the seeding script: `cd backend/seed-data && npm run seed`
- Verify database connection: `psql $DATABASE_URL -c "SELECT 1"`
- Check for migration errors

### Can't authenticate as test user
- Verify backend services are running
- Check `AppConfig.authServiceUrl` points to correct host
  - iOS Simulator: `http://localhost:3001`
  - Android Emulator: `http://10.0.2.2:3001`
  - Physical Device: `http://YOUR_COMPUTER_IP:3001`

### Real-time chat not working
- Verify both users are in the same match
- Check network tab for polling requests every 4 seconds
- Ensure chat service is running on port 3003
- Try pull-to-refresh manually

### Profiles repeat in discovery
- This is expected if you've seen fewer than 20 profiles
- 24-hour history prevents immediate repeats
- Reset history: Settings > Clear Discovery History (if implemented)
- Or: `cd backend/seed-data && npm run clean && npm run seed`

---

## Test Coverage Checklist

Use this checklist to ensure comprehensive testing:

### Authentication & Onboarding
- [ ] Test login with test user selector
- [ ] First-time profile setup flow
- [ ] Profile editing after setup
- [ ] Logout and re-login

### Discovery
- [ ] View profiles in discovery
- [ ] Like profiles
- [ ] Pass profiles
- [ ] Undo last action
- [ ] Apply age filters
- [ ] Apply distance filters
- [ ] Apply interest filters
- [ ] Clear filters
- [ ] Profile counter works
- [ ] No duplicate profiles (24h)
- [ ] End of profiles message

### Matching
- [ ] Create match by liking
- [ ] Match appears in matches tab
- [ ] Mutual match notification

### Messaging
- [ ] View existing conversations
- [ ] Send text messages
- [ ] Message appears immediately (optimistic UI)
- [ ] Real-time polling updates
- [ ] Retry failed messages
- [ ] Pull-to-refresh messages
- [ ] Character limit enforced
- [ ] Typing indicator shows

### Matches Screen
- [ ] View all matches
- [ ] Search matches by name
- [ ] Sort by recent activity
- [ ] Sort by newest
- [ ] Sort by name
- [ ] Unread message badges
- [ ] Last message preview
- [ ] Swipe to unmatch
- [ ] Long-press action menu
- [ ] Pull-to-refresh

### Subscription
- [ ] See upgrade banner in demo mode
- [ ] Like counter decrements
- [ ] Message counter decrements
- [ ] Premium gate dialog at limit
- [ ] Paywall shows pricing
- [ ] Free trial badge visible
- [ ] Feature comparison table
- [ ] Continue with limited access

### Safety
- [ ] Block user from chat
- [ ] Block user from discovery
- [ ] Blocked user disappears everywhere
- [ ] View blocked users in settings
- [ ] Unblock user
- [ ] Report user with reason
- [ ] Report submission succeeds
- [ ] Unmatch from swipe gesture
- [ ] Unmatch from action menu
- [ ] Undo unmatch (4s window)

### Profile
- [ ] View own profile
- [ ] Edit profile button works
- [ ] Save profile changes
- [ ] Changes reflect immediately
- [ ] View subscription status
- [ ] Access safety settings

### Performance
- [ ] Matches screen uses caching
- [ ] Discovery state persists
- [ ] Chat polling lifecycle correct
- [ ] Skeleton loading states
- [ ] Smooth animations
- [ ] No memory leaks

### Error Handling
- [ ] Offline banner shows when disconnected
- [ ] Retry button works
- [ ] Error messages are helpful
- [ ] Failed actions can be retried
- [ ] Validation errors shown inline

### UX Polish
- [ ] Loading skeletons (not spinners)
- [ ] Empty states with CTAs
- [ ] Confirmation dialogs for destructive actions
- [ ] Success feedback after actions
- [ ] Smooth transitions
- [ ] Consistent spacing/typography

---

## Automated Testing (Future)

Future enhancements to testing infrastructure:

### Unit Tests
- Test individual service methods
- Test data models
- Test utility functions

### Integration Tests
- Test API endpoints
- Test database operations
- Test authentication flow

### Widget Tests
- Test individual Flutter widgets
- Test user interactions
- Test state management

### E2E Tests
- Use Flutter's integration_test package
- Automate full user flows
- Test on real devices

---

## Reporting Issues

When reporting issues, please include:

1. **Test user used:** (e.g., Alex Chen - google_test001)
2. **Steps to reproduce:**
   - Step 1
   - Step 2
   - Step 3
3. **Expected behavior:** What should happen
4. **Actual behavior:** What actually happened
5. **Environment:**
   - Flutter version
   - iOS/Android version
   - Simulator/Emulator/Physical device
6. **Console logs:** Any error messages
7. **Screenshots/Screen recording:** If applicable

---

## Additional Resources

- **Backend Seeding:** `backend/seed-data/README.md`
- **UX Improvements:** `UX_IMPROVEMENTS_SUMMARY.md`
- **Safety Features:** `SAFETY_FEATURES_IMPLEMENTATION.md`
- **API Documentation:** `API_INTEGRATION.md`
- **Architecture:** `ARCHITECTURE.md`

---

Happy Testing! 🚀
