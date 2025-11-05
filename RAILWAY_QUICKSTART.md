# Railway Deployment - Quick Start Checklist

This is a condensed checklist for deploying to Railway. See `RAILWAY_DEPLOYMENT.md` for detailed instructions.

## Before You Start

- [ ] GitHub repository pushed and up to date
- [ ] Railway account created at [railway.app](https://railway.app)
- [ ] Railway CLI installed (optional): `npm install -g @railway/cli`

---

## Step-by-Step Deployment (30 minutes)

### 1. Create Project & Database (5 min)

- [ ] Go to [railway.app](https://railway.app/new)
- [ ] Click "New Project" → Name it "NoBSDating"
- [ ] Click "Add Service" → "Database" → "PostgreSQL"
- [ ] Wait for database to provision
- [ ] Note: DATABASE_URL is automatically created

### 2. Deploy Auth Service (5 min)

- [ ] Click "New Service" → "GitHub Repo" → Select `NoBSDating`
- [ ] **Service Settings:**
  - Name: `auth-service`
  - Root Directory: `backend/auth-service`
  - Start Command: `npm start`
- [ ] **Environment Variables:** (Settings → Variables → Raw Editor)
  ```
  PORT=3001
  JWT_SECRET=<paste-from-command-below>
  DATABASE_URL=${{Postgres.DATABASE_URL}}
  NODE_ENV=production
  CORS_ORIGIN=*
  ```
- [ ] Generate JWT Secret: `openssl rand -base64 64`
- [ ] Click "Deploy"
- [ ] **Networking:** Click "Generate Domain"
- [ ] Save URL: `https://auth-service-production-XXXX.up.railway.app`

### 3. Deploy Profile Service (5 min)

- [ ] Click "New Service" → "GitHub Repo" → Select `NoBSDating`
- [ ] **Service Settings:**
  - Name: `profile-service`
  - Root Directory: `backend/profile-service`
  - Start Command: `npm start`
- [ ] **Environment Variables:**
  ```
  PORT=3002
  DATABASE_URL=${{Postgres.DATABASE_URL}}
  NODE_ENV=production
  CORS_ORIGIN=*
  ```
- [ ] Click "Deploy"
- [ ] **Networking:** Click "Generate Domain"
- [ ] Save URL: `https://profile-service-production-XXXX.up.railway.app`

### 4. Deploy Chat Service (5 min)

- [ ] Click "New Service" → "GitHub Repo" → Select `NoBSDating`
- [ ] **Service Settings:**
  - Name: `chat-service`
  - Root Directory: `backend/chat-service`
  - Start Command: `npm start`
- [ ] **Environment Variables:**
  ```
  PORT=3003
  DATABASE_URL=${{Postgres.DATABASE_URL}}
  NODE_ENV=production
  CORS_ORIGIN=*
  ```
- [ ] Click "Deploy"
- [ ] **Networking:** Click "Generate Domain"
- [ ] Save URL: `https://chat-service-production-XXXX.up.railway.app`

### 5. Run Database Migrations (5 min)

**Option A - Via Railway CLI:**
```bash
# Install CLI if not already
npm install -g @railway/cli

# Link to project
railway login
railway link

# Get DATABASE_URL
railway variables get DATABASE_URL

# Run migrations
cd backend/migrations
export DATABASE_URL="postgresql://user:pass@host:port/db"
./run_migration.sh
```

**Option B - Manually via psql:**
```bash
# Connect to Railway database
railway connect postgres

# Run each migration
\i /path/to/backend/migrations/001_create_users_and_profiles.sql
\i /path/to/backend/migrations/002_create_matches_and_messages.sql
\i /path/to/backend/migrations/003_create_safety_tables.sql

\q
```

### 6. Test Deployment (5 min)

- [ ] **Test Auth Service:**
  ```bash
  curl https://auth-service-production-XXXX.up.railway.app/health
  # Expected: {"status":"ok","service":"auth-service"}
  ```

- [ ] **Test Profile Service:**
  ```bash
  curl https://profile-service-production-XXXX.up.railway.app/health
  # Expected: {"status":"ok","service":"profile-service"}
  ```

- [ ] **Test Chat Service:**
  ```bash
  curl https://chat-service-production-XXXX.up.railway.app/health
  # Expected: {"status":"ok","service":"chat-service"}
  ```

- [ ] **Check Database:**
  ```bash
  railway connect postgres
  \dt
  # Should show: users, profiles, matches, messages, blocks, reports
  \q
  ```

### 7. Update Flutter App (5 min)

- [ ] Edit `frontend/lib/config/app_config.dart`
- [ ] Replace localhost URLs with Railway URLs:
  ```dart
  static const String authServiceUrl =
    'https://auth-service-production-XXXX.up.railway.app';
  static const String profileServiceUrl =
    'https://profile-service-production-XXXX.up.railway.app';
  static const String chatServiceUrl =
    'https://chat-service-production-XXXX.up.railway.app';
  ```
- [ ] Or use environment variables (recommended):
  ```bash
  flutter run --dart-define=AUTH_URL=https://auth-service-production-XXXX.up.railway.app
  ```

### 8. Optional: Seed Test Data

**⚠️ Only for testing environments!**

```bash
# Get DATABASE_URL from Railway
railway variables get DATABASE_URL

# Run seed script
cd backend/seed-data
npm install
export DATABASE_URL="postgresql://..."
npm run seed
```

---

## Verification Checklist

- [ ] All 3 services show "Active" status in Railway dashboard
- [ ] Health endpoints return 200 OK
- [ ] Database has all tables (users, profiles, matches, messages, blocks, reports)
- [ ] Flutter app can connect to services
- [ ] Can sign in with Google/Apple
- [ ] Can create profile
- [ ] Can browse discovery
- [ ] Can send messages

---

## Quick Commands

```bash
# View logs for a service
railway logs -f

# Check service status
railway status

# Connect to database
railway connect postgres

# Set environment variable
railway variables set KEY=value

# Restart service
railway restart

# Open Railway dashboard
railway open
```

---

## Troubleshooting

### Service won't start
→ Check logs: `railway logs`
→ Verify environment variables set
→ Ensure Root Directory is correct

### Can't connect to database
→ Verify DATABASE_URL: `railway variables get DATABASE_URL`
→ Check Postgres service is running
→ Re-link: `railway link`

### CORS errors
→ Add CORS_ORIGIN variable to service
→ Set to `*` for testing or specific domain for production

### 404 errors
→ Ensure "Generate Domain" was clicked
→ Check service is deployed and active
→ Verify health endpoint works

---

## Cost Estimate

**Hobby Plan ($5/month credit):**
- PostgreSQL: ~$5/month
- Auth Service: ~$2-3/month
- Profile Service: ~$2-3/month
- Chat Service: ~$2-3/month
- **Total: ~$12-14/month**

First month mostly covered by $5 credit!

---

## Next Steps After Deployment

1. **Monitor logs** for errors
2. **Test all features** from Flutter app
3. **Set up custom domain** (optional)
4. **Configure backups** (Railway Pro)
5. **Add monitoring alerts**
6. **Load test** the application
7. **Security review** before production

---

## Support

- Railway Docs: https://docs.railway.app
- Railway Discord: https://discord.gg/railway
- Project Docs: See `RAILWAY_DEPLOYMENT.md` for detailed guide

---

**Deployment complete!** Your NoBSDating app is now live on Railway 🚀

**Service URLs:**
- Auth: `https://auth-service-production-XXXX.up.railway.app`
- Profile: `https://profile-service-production-XXXX.up.railway.app`
- Chat: `https://chat-service-production-XXXX.up.railway.app`
