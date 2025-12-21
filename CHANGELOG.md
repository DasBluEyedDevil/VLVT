# VLVT - Changelog

## [Unreleased] - 2025-12-22 - Beta Testing - Hardening

### Removed
- Test endpoints in auth/profile services (`/auth/test-login`, `/auth/seed-test-users`, `/auth/init-database`, `/profile/seed-test-profiles`)
- `ENABLE_TEST_ENDPOINTS` gating

### Changed
- Chat service now requires existing users for match creation (no auto-create)
- Backend root start script now fails fast with guidance
- Android release signing uses `key.properties` and blocks unsigned release builds
- Documentation updated to reflect current auth flow and test user usage

### Available Test Accounts
- `google_test001` through `google_test020`
- Generate JWTs manually (see `backend/seed-data/README.md`)

### Status
- **Test Users:** AVAILABLE
- **Database Seeding:** COMPLETE
- **Beta Testing:** IN PROGRESS
---

## [1.0.0] - 2025-11-13 - Beta Prep Session

### Fixed
- **Test Infrastructure** - Made all backend services testable
  - Services no longer start server when imported in test mode
  - Winston logger skips file writes in test environment
  - Environment variable validation conditional on test mode
  - Fixed TypeScript return types for logger methods

- **Backend Services Export**
  - `backend/auth-service/src/index.ts` - Exports app for testing
  - `backend/profile-service/src/index.ts` - Exports app for testing
  - `backend/chat-service/src/index.ts` - Exports app for testing

- **Winston Logger Test Compatibility**
  - `backend/*/src/utils/logger.ts` - All 3 services updated
  - No file transport in test mode
  - Silent mode enabled for tests
  - Fixed Sentry integration return type

### Changed
- **Test Environment Handling**
  - Env validation skipped in test mode (NODE_ENV=test)
  - JWT_SECRET defaults to 'test-secret' in tests
  - Database connection pool respects test environment

### Completed
- ✅ Dependencies installed (all services, 0 vulnerabilities)
- ✅ Test infrastructure functional (tests now run)
- ✅ All backend services testable
- ✅ Winston logger test-mode compatible

### Status
- **Test Infrastructure:** ✅ WORKING
- **Production Code:** ✅ READY FOR BETA
- **Beta Documentation:** ✅ COMPLETE
- **Next Step:** Deploy to Railway & configure environments

---

## [1.0.0] - 2025-11-13 - Phase 2 Complete

### Added
- **Testing Infrastructure** (158 backend + 77 frontend tests)
  - Jest + TypeScript configuration for all 3 backend services
  - Flutter widget and unit tests
  - Coverage thresholds (30% backend, 20% frontend)

- **Rate Limiting** (20+ endpoints protected)
  - Redis-backed distributed rate limiting
  - Memory fallback for development
  - 9 unique rate limiters configured

- **Structured Logging** (Winston)
  - JSON-formatted logs with rotation
  - PII redaction (emails, tokens, passwords)
  - Sentry integration for errors
  - Replaced 30+ console.log statements

- **Beta Testing Infrastructure**
  - 9 comprehensive documents (100+ pages)
  - In-app feedback widget
  - GitHub issue templates
  - Professional communication templates
  - Metrics framework with industry benchmarks

- **Firebase Analytics**
  - 20+ custom events tracked
  - User properties for segmentation
  - Complete funnel analysis support
  - Integration with Crashlytics

### Security Improvements
- Database connection pooling configured
- PII redaction in all logs
- Rate limiting on all critical endpoints
- Comprehensive error tracking

### Documentation
- `BETA_TESTING_PLAN.md` - 4-6 week strategy
- `BETA_METRICS.md` - Analytics framework
- `ANALYTICS_GUIDE.md` - Firebase integration guide
- `RATE_LIMITING_AND_LOGGING_REPORT.md` - Infrastructure summary
- `PHASE2_COMPLETION_SUMMARY.md` - Complete phase report

---

## [0.2.0] - 2025-11-13 - Phase 1 Complete

### Security Fixes (Critical)
1. **Apple Sign-In Authentication** - Fixed token verification
   - Now uses `apple-signin-auth` library
   - Proper cryptographic verification
   - Eliminated authentication bypass vulnerability

2. **Authorization (IDOR Fixes)**
   - Profile Service: 5 endpoints secured with JWT + ownership checks
   - Chat Service: 11 endpoints secured with JWT + match participation checks

3. **Input Validation**
   - Installed `express-validator` on all services
   - Comprehensive validation rules for all user inputs
   - Age verification (18+) enforced

4. **CORS Configuration**
   - Environment-based CORS origins
   - Proper credential handling
   - Eliminated CSRF attack vector

5. **Security Headers**
   - Installed Helmet middleware on all services
   - 10+ security headers added

6. **Rate Limiting (Initial)**
   - Basic rate limiting on auth endpoints
   - Additional limits in Phase 2

### Added
- JWT authentication middleware (all 3 services)
- Sentry error tracking integration
- Firebase Crashlytics for mobile
- Frontend URL auto-configuration (debug mode detection)
- Safety Settings navigation from Profile screen
- Legal document templates (Privacy Policy, Terms of Service)

### Documentation
- `PHASE1_COMPLETION_SUMMARY.md` - Complete phase report
- `BETA_READINESS_REPORT.md` - Security assessment
- `PRIVACY_POLICY.md` - GDPR + CCPA template
- `TERMS_OF_SERVICE.md` - Comprehensive terms
- `FIREBASE_SETUP.md` - Complete Firebase guide

### Security Score Improvement
- **Before:** 40/100 (NOT READY)
- **After:** ~75/100 (CONDITIONALLY BETA-READY)

---

## [0.1.0] - 2025-11-12 - Initial Development

### Added
- Basic Flutter app structure
- Three backend microservices (auth, profile, chat)
- Apple and Google Sign-In
- Profile creation and management
- Discovery feed with swipe actions
- Match and messaging system
- Safety features (block, report, unmatch)
- RevenueCat subscription integration

### Known Issues
- No JWT authentication (CRITICAL)
- No authorization checks (CRITICAL)
- No input validation (CRITICAL)
- Open CORS configuration (CRITICAL)
- No security headers (HIGH)
- No monitoring/error tracking (HIGH)

---

## Version History Summary

| Version | Date | Status | Security Score | Notes |
|---------|------|--------|----------------|-------|
| Unreleased | 2025-11-13 | Beta Prep | 85/100 | Test infrastructure complete |
| 1.0.0 | 2025-11-13 | Phase 2 Done | 85/100 | Public beta ready |
| 0.2.0 | 2025-11-13 | Phase 1 Done | 75/100 | Internal beta ready |
| 0.1.0 | 2025-11-12 | Initial | 40/100 | Not production ready |

---

**Changelog Format:** Based on [Keep a Changelog](https://keepachangelog.com/)
**Versioning:** Semantic Versioning (MAJOR.MINOR.PATCH)

