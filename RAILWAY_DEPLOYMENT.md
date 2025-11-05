# Deploying NoBS Dating to Railway

This guide walks you through deploying the complete NoBSDating application to Railway for testing and production use.

## Overview

Railway is a modern PaaS that simplifies deployment with:
- ✅ Automatic GitHub deployments
- ✅ Built-in PostgreSQL database
- ✅ Free $5/month credit (Hobby plan)
- ✅ Easy environment variable management
- ✅ Automatic SSL certificates
- ✅ Simple scaling

**What we'll deploy:**
- 1 PostgreSQL database
- 3 backend services (auth, profile, chat)
- Total estimated cost: ~$10-20/month on Hobby plan

---

## Prerequisites

- [x] GitHub account with NoBSDating repository
- [x] Railway account (sign up at [railway.app](https://railway.app))
- [x] Git installed locally
- [x] Railway CLI installed (optional but recommended)

---

## Part 1: Initial Setup

### 1.1 Create Railway Account

1. Go to [railway.app](https://railway.app)
2. Click "Start a New Project"
3. Sign in with GitHub (easiest option)
4. Authorize Railway to access your repositories

### 1.2 Install Railway CLI (Optional)

**Windows (PowerShell):**
```powershell
iwr https://railway.app/install.ps1 | iex
```

**macOS/Linux:**
```bash
sh -c "$(curl -fsSL https://railway.app/install.sh)"
```

**Verify installation:**
```bash
railway --version
railway login
```

---

## Part 2: Deploy PostgreSQL Database

### 2.1 Create Database Service

**Via Railway Dashboard:**
1. Click "New Project"
2. Name it "NoBSDating"
3. Click "Add Service" → "Database" → "PostgreSQL"
4. Railway automatically provisions the database

**Via CLI:**
```bash
railway init
railway add --database postgresql
```

### 2.2 Note Database Connection Details

Railway automatically creates these environment variables:
- `DATABASE_URL` - Full connection string
- `PGHOST` - Database host
- `PGPORT` - Database port (usually 5432)
- `PGUSER` - Database user
- `PGPASSWORD` - Database password
- `PGDATABASE` - Database name

**To view connection string:**
```bash
railway variables get DATABASE_URL
```

Or in the dashboard: Service → Variables tab

---

## Part 3: Deploy Backend Services

You'll deploy 3 separate services that all connect to the same PostgreSQL database.

### 3.1 Deploy Auth Service

#### Via Railway Dashboard:

1. Click "New Service" → "GitHub Repo"
2. Select your `NoBSDating` repository
3. Railway detects it as a Node.js app
4. Configure the service:
   - **Name:** `auth-service`
   - **Root Directory:** `backend/auth-service`
   - **Build Command:** `npm install`
   - **Start Command:** `npm start`
   - **Port:** 3001

5. Add Environment Variables (Settings → Variables):
   ```
   PORT=3001
   JWT_SECRET=<generate-strong-secret>
   DATABASE_URL=${{Postgres.DATABASE_URL}}
   NODE_ENV=production
   ```

6. Click "Deploy"

#### Via CLI:

```bash
cd backend/auth-service
railway up
railway variables set PORT=3001
railway variables set JWT_SECRET="your-secret-here"
railway variables set DATABASE_URL='${{Postgres.DATABASE_URL}}'
railway variables set NODE_ENV=production
```

### 3.2 Deploy Profile Service

**Via Dashboard:**
1. Click "New Service" → "GitHub Repo"
2. Select `NoBSDating` repository
3. Configure:
   - **Name:** `profile-service`
   - **Root Directory:** `backend/profile-service`
   - **Build Command:** `npm install`
   - **Start Command:** `npm start`
   - **Port:** 3002

4. Add Environment Variables:
   ```
   PORT=3002
   DATABASE_URL=${{Postgres.DATABASE_URL}}
   NODE_ENV=production
   ```

**Via CLI:**
```bash
cd backend/profile-service
railway up
railway variables set PORT=3002
railway variables set DATABASE_URL='${{Postgres.DATABASE_URL}}'
railway variables set NODE_ENV=production
```

### 3.3 Deploy Chat Service

**Via Dashboard:**
1. Click "New Service" → "GitHub Repo"
2. Select `NoBSDating` repository
3. Configure:
   - **Name:** `chat-service`
   - **Root Directory:** `backend/chat-service`
   - **Build Command:** `npm install`
   - **Start Command:** `npm start`
   - **Port:** 3003

4. Add Environment Variables:
   ```
   PORT=3003
   DATABASE_URL=${{Postgres.DATABASE_URL}}
   NODE_ENV=production
   ```

**Via CLI:**
```bash
cd backend/chat-service
railway up
railway variables set PORT=3003
railway variables set DATABASE_URL='${{Postgres.DATABASE_URL}}'
railway variables set NODE_ENV=production
```

---

## Part 4: Configure Service URLs

### 4.1 Generate Public URLs

For each service (auth, profile, chat):

**Via Dashboard:**
1. Open service → Settings
2. Scroll to "Networking"
3. Click "Generate Domain"
4. Railway creates: `service-name.up.railway.app`

**Via CLI:**
```bash
railway domain  # In each service directory
```

**Expected URLs:**
```
Auth Service: https://auth-service-production-xxxx.up.railway.app
Profile Service: https://profile-service-production-xxxx.up.railway.app
Chat Service: https://chat-service-production-xxxx.up.railway.app
```

### 4.2 Enable CORS

Each service needs to allow requests from your Flutter app and other services.

Add to each service's environment variables:
```
CORS_ORIGIN=*
```

Or for production (more secure):
```
CORS_ORIGIN=https://your-flutter-app-domain.com,https://auth-service.up.railway.app
```

---

## Part 5: Run Database Migrations

### 5.1 Via Railway CLI (Recommended)

```bash
# Connect to your Railway project
cd /path/to/NoBSDating
railway link

# Get the DATABASE_URL
railway variables get DATABASE_URL

# Run migrations locally against Railway database
cd backend/migrations
export DATABASE_URL="<your-railway-database-url>"
./run_migration.sh
```

### 5.2 Via Railway Shell (Alternative)

```bash
# Open shell in auth-service
railway shell

# Inside the shell
cd ../migrations
psql $DATABASE_URL -f 001_create_users_and_profiles.sql
psql $DATABASE_URL -f 002_create_matches_and_messages.sql
psql $DATABASE_URL -f 003_create_safety_tables.sql
exit
```

### 5.3 Verify Migrations

```bash
railway connect postgres

# Inside psql
\dt
# Should show: users, profiles, matches, messages, blocks, reports

\q
```

---

## Part 6: Seed Test Data (Optional)

### 6.1 Seed Test Users

Only for testing environments:

```bash
# Get DATABASE_URL
railway variables get DATABASE_URL

# Run seed script locally
cd backend/seed-data
export DATABASE_URL="<your-railway-database-url>"
npm run seed
```

**⚠️ WARNING:** Only seed test data in development/staging environments, not production!

---

## Part 7: Configure Flutter App

### 7.1 Update AppConfig

Edit `frontend/lib/config/app_config.dart`:

```dart
class AppConfig {
  // Railway Production URLs
  static const String authServiceUrl =
    String.fromEnvironment(
      'AUTH_URL',
      defaultValue: 'https://auth-service-production-xxxx.up.railway.app'
    );

  static const String profileServiceUrl =
    String.fromEnvironment(
      'PROFILE_URL',
      defaultValue: 'https://profile-service-production-xxxx.up.railway.app'
    );

  static const String chatServiceUrl =
    String.fromEnvironment(
      'CHAT_URL',
      defaultValue: 'https://chat-service-production-xxxx.up.railway.app'
    );

  static const String revenueCatApiKey =
    String.fromEnvironment('REVENUECAT_API_KEY');
}
```

### 7.2 Build and Test Flutter App

**For testing:**
```bash
cd frontend
flutter run --dart-define=AUTH_URL=https://auth-service.up.railway.app \
            --dart-define=PROFILE_URL=https://profile-service.up.railway.app \
            --dart-define=CHAT_URL=https://chat-service.up.railway.app
```

**For production build:**
```bash
# iOS
flutter build ios --dart-define=AUTH_URL=https://... \
                   --dart-define=PROFILE_URL=https://... \
                   --dart-define=CHAT_URL=https://...

# Android
flutter build apk --release --dart-define=AUTH_URL=https://... \
                            --dart-define=PROFILE_URL=https://... \
                            --dart-define=CHAT_URL=https://...
```

---

## Part 8: Environment Variables Reference

### Required Variables Per Service

#### Auth Service
| Variable | Description | Example |
|----------|-------------|---------|
| `PORT` | Service port | `3001` |
| `JWT_SECRET` | Secret for JWT signing | `openssl rand -base64 64` |
| `DATABASE_URL` | PostgreSQL connection | `${{Postgres.DATABASE_URL}}` |
| `NODE_ENV` | Environment | `production` |
| `CORS_ORIGIN` | Allowed origins | `*` or specific domains |

#### Profile Service
| Variable | Description | Example |
|----------|-------------|---------|
| `PORT` | Service port | `3002` |
| `DATABASE_URL` | PostgreSQL connection | `${{Postgres.DATABASE_URL}}` |
| `NODE_ENV` | Environment | `production` |
| `CORS_ORIGIN` | Allowed origins | `*` or specific domains |

#### Chat Service
| Variable | Description | Example |
|----------|-------------|---------|
| `PORT` | Service port | `3003` |
| `DATABASE_URL` | PostgreSQL connection | `${{Postgres.DATABASE_URL}}` |
| `NODE_ENV` | Environment | `production` |
| `CORS_ORIGIN` | Allowed origins | `*` or specific domains |

### Generate Strong JWT Secret

```bash
openssl rand -base64 64
```

Or online: [randomkeygen.com](https://randomkeygen.com/)

---

## Part 9: Monitoring and Logs

### 9.1 View Logs

**Via Dashboard:**
1. Click on any service
2. Go to "Deployments" tab
3. Click on latest deployment
4. View build and runtime logs

**Via CLI:**
```bash
railway logs  # In any service directory
railway logs -f  # Follow logs in real-time
```

### 9.2 Check Service Health

Test each service:

```bash
# Auth Service Health
curl https://auth-service.up.railway.app/health

# Profile Service Health
curl https://profile-service.up.railway.app/health

# Chat Service Health
curl https://chat-service.up.railway.app/health
```

Expected response:
```json
{
  "status": "ok",
  "service": "auth-service"
}
```

### 9.3 Monitor Database

**Via CLI:**
```bash
railway connect postgres

# Check connections
SELECT count(*) FROM pg_stat_activity;

# Check table sizes
SELECT
  schemaname,
  tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

\q
```

---

## Part 10: Custom Domains (Optional)

### 10.1 Add Custom Domain

**Via Dashboard:**
1. Open service → Settings
2. Scroll to "Networking"
3. Click "Add Custom Domain"
4. Enter your domain: `api.yourdomain.com`
5. Add CNAME record in your DNS provider:
   - **Type:** CNAME
   - **Name:** api (or subdomain)
   - **Value:** service-name.up.railway.app

### 10.2 SSL Certificates

Railway automatically provisions SSL certificates via Let's Encrypt for all domains (both Railway domains and custom domains).

---

## Part 11: Deployment Workflow

### 11.1 Automatic Deployments

Railway auto-deploys on every push to your main branch:

1. Push code to GitHub
2. Railway detects changes
3. Automatically builds and deploys
4. Zero-downtime deployment

### 11.2 Manual Deployments

**Via Dashboard:**
1. Service → Deployments
2. Click "Deploy"

**Via CLI:**
```bash
railway up  # Deploy current directory
```

### 11.3 Rollback

**Via Dashboard:**
1. Service → Deployments
2. Find previous successful deployment
3. Click "..." → "Redeploy"

**Via CLI:**
```bash
railway rollback
```

---

## Part 12: Cost Estimation

### Railway Pricing (as of 2024)

**Hobby Plan ($5/month credit):**
- Includes: $5 usage credit
- After credit: Pay-as-you-go
- Good for: Testing, small projects

**Typical NoBS Dating Costs:**
- PostgreSQL: ~$5/month (512MB)
- Auth Service: ~$2-3/month (512MB RAM)
- Profile Service: ~$2-3/month (512MB RAM)
- Chat Service: ~$2-3/month (512MB RAM)
- **Total: ~$11-14/month**

**Pro Plan ($20/month):**
- Includes: $20 usage credit
- Priority support
- More resources

### Cost Optimization Tips

1. **Use Hobby plan for testing**
2. **Scale services as needed** (Railway auto-scales)
3. **Monitor usage** in Dashboard → Usage
4. **Optimize queries** to reduce database load
5. **Use caching** (implemented in the app)

---

## Part 13: Security Checklist

Before going to production:

- [ ] Generate strong JWT_SECRET (64+ characters)
- [ ] Set NODE_ENV=production on all services
- [ ] Disable test login endpoint (auto-disabled in production)
- [ ] Configure CORS_ORIGIN with specific domains (not *)
- [ ] Enable Railway's built-in DDoS protection
- [ ] Review database permissions
- [ ] Set up backup strategy
- [ ] Add rate limiting (already implemented)
- [ ] Review logs for security issues
- [ ] Test authentication flows
- [ ] Verify SSL certificates are active

---

## Part 14: Troubleshooting

### Service Won't Start

**Check logs:**
```bash
railway logs
```

**Common issues:**
- Missing environment variables
- Database connection failed
- Port already in use
- Build failed

**Solutions:**
1. Verify all environment variables set
2. Check DATABASE_URL is correct
3. Ensure PORT matches service config
4. Review build logs for errors

### Database Connection Failed

**Check connection:**
```bash
railway variables get DATABASE_URL
railway connect postgres  # Should open psql
```

**Common issues:**
- DATABASE_URL not set
- Database not provisioned
- Connection string format wrong

**Solution:**
```bash
# Re-link database to service
railway link
railway variables set DATABASE_URL='${{Postgres.DATABASE_URL}}'
```

### 404 Not Found

**Check service URL:**
```bash
railway status
```

**Verify domain:**
- Dashboard → Service → Settings → Networking
- Ensure "Generate Domain" was clicked

### CORS Errors

**Add CORS configuration:**
```bash
railway variables set CORS_ORIGIN="*"  # For testing
# Or
railway variables set CORS_ORIGIN="https://yourdomain.com"  # For production
```

Then restart service:
```bash
railway restart
```

### High Memory Usage

**Check metrics:**
- Dashboard → Service → Metrics

**Solutions:**
1. Upgrade to larger plan
2. Optimize queries
3. Add pagination
4. Review memory leaks

### Slow Response Times

**Check logs for slow queries:**
```bash
railway logs | grep "slow"
```

**Solutions:**
1. Add database indexes
2. Optimize N+1 queries (already done)
3. Enable caching (already implemented)
4. Scale database

---

## Part 15: Backup and Restore

### 15.1 Backup Database

**Via CLI:**
```bash
# Get database URL
export DB_URL=$(railway variables get DATABASE_URL)

# Backup
pg_dump $DB_URL > backup_$(date +%Y%m%d_%H%M%S).sql

# Or backup specific tables
pg_dump $DB_URL -t users -t profiles > backup_users.sql
```

**Via Railway Dashboard:**
Railway Postgres includes automatic daily backups (Pro plan).

### 15.2 Restore Database

```bash
# Restore from backup
psql $DB_URL < backup_20240101_120000.sql

# Or via Railway
railway connect postgres
\i backup_20240101_120000.sql
\q
```

---

## Part 16: Testing Checklist

After deployment, test all features:

### API Endpoints
- [ ] Auth service health check
- [ ] Profile service health check
- [ ] Chat service health check
- [ ] Sign in with Google
- [ ] Sign in with Apple (iOS only)
- [ ] Profile creation
- [ ] Profile editing
- [ ] Discovery profiles
- [ ] Create match
- [ ] Send message
- [ ] Block user
- [ ] Report user

### Flutter App
- [ ] Authentication works
- [ ] Profile setup flows
- [ ] Discovery screen loads
- [ ] Can like/pass profiles
- [ ] Matches appear
- [ ] Chat messages send/receive
- [ ] Real-time polling works
- [ ] Subscription flow works
- [ ] Offline mode shows banner

### Performance
- [ ] Response times < 1 second
- [ ] No memory leaks (check Railway metrics)
- [ ] Database queries optimized
- [ ] Caching working properly

---

## Part 17: Next Steps

### For Testing:
1. Share Railway URLs with testers
2. Seed test data (if needed)
3. Monitor logs for errors
4. Gather feedback

### For Production:
1. Set up custom domain
2. Configure RevenueCat for subscriptions
3. Set up error tracking (Sentry, etc.)
4. Enable monitoring alerts
5. Set up CI/CD pipeline
6. Configure backups
7. Load test the application
8. Security audit
9. Submit to app stores

---

## Part 18: Additional Resources

**Railway Documentation:**
- [Railway Docs](https://docs.railway.app/)
- [PostgreSQL Guide](https://docs.railway.app/databases/postgresql)
- [Node.js Deployment](https://docs.railway.app/deploy/deployments)

**Project Documentation:**
- `ARCHITECTURE.md` - System architecture
- `API_INTEGRATION.md` - API documentation
- `TESTING.md` - Testing guide
- `SAFETY_FEATURES_IMPLEMENTATION.md` - Safety features

**Support:**
- Railway Discord: [discord.gg/railway](https://discord.gg/railway)
- Railway Status: [status.railway.app](https://status.railway.app)

---

## Quick Reference Commands

```bash
# Login to Railway
railway login

# Link to project
railway link

# View variables
railway variables

# Set variable
railway variables set KEY=value

# View logs
railway logs -f

# Connect to database
railway connect postgres

# Deploy service
railway up

# Check status
railway status

# Restart service
railway restart

# Open dashboard
railway open
```

---

## Summary

You've now deployed:
- ✅ PostgreSQL database on Railway
- ✅ Auth service with JWT authentication
- ✅ Profile service with user management
- ✅ Chat service with messaging
- ✅ Automatic deployments on Git push
- ✅ SSL certificates for all domains
- ✅ Monitoring and logging

**Total time: ~30-45 minutes**
**Total cost: ~$11-14/month**

Your NoBSDating app is now live and ready for testing! 🚀
