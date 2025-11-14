import dotenv from 'dotenv';
// Load environment variables first
dotenv.config();

// Initialize Sentry before any other imports
import * as Sentry from '@sentry/node';

if (process.env.SENTRY_DSN) {
  Sentry.init({
    dsn: process.env.SENTRY_DSN,
    environment: process.env.NODE_ENV || 'development',
    tracesSampleRate: 0.1, // 10% of transactions for performance monitoring
  });
}

import express, { Request, Response } from 'express';
import cors from 'cors';
import helmet from 'helmet';
import jwt from 'jsonwebtoken';
import { Pool } from 'pg';
import { OAuth2Client } from 'google-auth-library';
import appleSignin from 'apple-signin-auth';
import migrateRouter from './migrate-endpoint';
import logger from './utils/logger';
import { authLimiter, verifyLimiter, generalLimiter } from './middleware/rate-limiter';

const app = express();
const PORT = process.env.PORT || 3001;

// Log initialization
if (process.env.SENTRY_DSN) {
  logger.info('Sentry error tracking enabled', { environment: process.env.NODE_ENV || 'development' });
} else {
  logger.info('Sentry error tracking disabled (SENTRY_DSN not set)');
}

// In test environment, these are set in tests/setup.ts
if (!process.env.JWT_SECRET && process.env.NODE_ENV !== 'test') {
  logger.error('JWT_SECRET environment variable is required');
  process.exit(1);
}
if (!process.env.DATABASE_URL && process.env.NODE_ENV !== 'test') {
  logger.error('DATABASE_URL environment variable is required');
  process.exit(1);
}
const JWT_SECRET = process.env.JWT_SECRET || 'test-secret';

// CORS origin from environment variable
const CORS_ORIGIN = process.env.CORS_ORIGIN || 'http://localhost:19006';

// Initialize Google OAuth2 client
const googleClient = new OAuth2Client();

// Initialize PostgreSQL connection pool with proper configuration
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: 20, // Maximum number of clients in the pool
  idleTimeoutMillis: 30000, // Close idle clients after 30 seconds
  connectionTimeoutMillis: 2000, // Return an error after 2 seconds if connection cannot be established
  ssl: process.env.DATABASE_URL?.includes('railway')
    ? { rejectUnauthorized: true }
    : false,
});

// Database connection event handlers
pool.on('connect', (client) => {
  logger.info('New database connection established');
});

pool.on('acquire', (client) => {
  logger.debug('Database client acquired from pool');
});

pool.on('remove', (client) => {
  logger.debug('Database client removed from pool');
});

pool.on('error', (err, client) => {
  logger.error('Unexpected database connection error', {
    error: err.message,
    stack: err.stack
  });
});

// Security middleware
app.use(helmet());
app.use(cors({
  origin: CORS_ORIGIN,
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization']
}));
app.use(express.json({ limit: '10kb' }));

// TEMPORARY: Migration endpoint (remove after migrations complete)
// WARNING: This endpoint should be removed in production
// Migrations should be run via Railway CLI or separate script
// app.use('/admin', migrateRouter);

// Health check endpoint
app.get('/health', (req: Request, res: Response) => {
  res.json({ status: 'ok', service: 'auth-service' });
});

// Sign in with Apple endpoint
app.post('/auth/apple', authLimiter, async (req: Request, res: Response) => {
  try {
    const { identityToken } = req.body;

    if (!identityToken) {
      return res.status(400).json({ success: false, error: 'identityToken is required' });
    }

    // Verify the Apple identity token using apple-signin-auth
    // This properly verifies the token signature against Apple's public keys
    try {
      const appleIdTokenClaims = await appleSignin.verifyIdToken(identityToken, {
        // Audience should be your app's bundle ID/service ID from Apple
        // audience: process.env.APPLE_CLIENT_ID, // Uncomment and set in production
        nonce: 'nonce' // Optional: verify nonce if you passed one during sign-in
      });

      if (!appleIdTokenClaims || !appleIdTokenClaims.sub) {
        return res.status(401).json({ success: false, error: 'Invalid identity token claims' });
      }

      // Extract verified providerId and email from token claims
      const providerId = `apple_${appleIdTokenClaims.sub}`;
      const email = appleIdTokenClaims.email || `user_${appleIdTokenClaims.sub}@apple.example.com`;
      const provider = 'apple';

      // Upsert user in database
      const result = await pool.query(
        `INSERT INTO users (id, provider, email)
         VALUES ($1, $2, $3)
         ON CONFLICT (id)
         DO UPDATE SET updated_at = CURRENT_TIMESTAMP, email = $3
         RETURNING id, provider, email`,
        [providerId, provider, email]
      );

      const user = result.rows[0];
      const token = jwt.sign(
        { userId: user.id, provider: user.provider, email: user.email },
        JWT_SECRET,
        { expiresIn: '7d' }
      );

      res.json({
        success: true,
        token,
        userId: user.id,
        provider: user.provider
      });
    } catch (verifyError) {
      logger.error('Apple token verification failed', { error: verifyError });
      return res.status(401).json({ success: false, error: 'Failed to verify Apple identity token' });
    }
  } catch (error) {
    logger.error('Apple authentication error', { error });
    res.status(500).json({ success: false, error: 'Authentication failed' });
  }
});

// Sign in with Google endpoint
app.post('/auth/google', authLimiter, async (req: Request, res: Response) => {
  try {
    const { idToken } = req.body;
    
    if (!idToken) {
      return res.status(400).json({ success: false, error: 'idToken is required' });
    }
    
    // Verify the Google ID token
    const ticket = await googleClient.verifyIdToken({
      idToken: idToken,
      audience: process.env.GOOGLE_CLIENT_ID, // Optional: verify audience
    });
    
    const payload = ticket.getPayload();
    if (!payload || !payload.sub) {
      return res.status(401).json({ success: false, error: 'Invalid token payload' });
    }
    
    // Extract real providerId and email from verified token
    const providerId = `google_${payload.sub}`;
    const email = payload.email || `user_${payload.sub}@google.example.com`;
    const provider = 'google';
    
    // Upsert user in database
    const result = await pool.query(
      `INSERT INTO users (id, provider, email) 
       VALUES ($1, $2, $3) 
       ON CONFLICT (id) 
       DO UPDATE SET updated_at = CURRENT_TIMESTAMP, email = $3
       RETURNING id, provider, email`,
      [providerId, provider, email]
    );
    
    const user = result.rows[0];
    const token = jwt.sign(
      { userId: user.id, provider: user.provider, email: user.email },
      JWT_SECRET,
      { expiresIn: '7d' }
    );
    
    res.json({
      success: true,
      token,
      userId: user.id,
      provider: user.provider
    });
  } catch (error) {
    logger.error('Google authentication error', { error });
    res.status(500).json({ success: false, error: 'Authentication failed' });
  }
});

// Verify token endpoint (with rate limiting)
app.post('/auth/verify', verifyLimiter, (req: Request, res: Response) => {
  try {
    const { token } = req.body;
    
    if (!token) {
      return res.status(401).json({ success: false, error: 'No token provided' });
    }
    
    const decoded = jwt.verify(token, JWT_SECRET);
    res.json({ success: true, decoded });
  } catch (error) {
    res.status(401).json({ success: false, error: 'Invalid token' });
  }
});

// Test login endpoint (ONLY FOR DEVELOPMENT/TESTING/BETA)
// This bypasses OAuth and allows direct login with any user ID
// Enable in beta testing with ENABLE_TEST_ENDPOINTS=true
if (process.env.NODE_ENV !== 'production' || process.env.ENABLE_TEST_ENDPOINTS === 'true') {
  app.post('/auth/test-login', async (req: Request, res: Response) => {
    try {
      const { userId } = req.body;

      if (!userId) {
        return res.status(400).json({ success: false, error: 'userId is required' });
      }

      // Verify the user exists in the database
      const result = await pool.query(
        'SELECT * FROM users WHERE id = $1',
        [userId]
      );

      if (result.rows.length === 0) {
        return res.status(404).json({ success: false, error: 'User not found' });
      }

      const user = result.rows[0];
      const token = jwt.sign(
        { userId: user.id, provider: user.provider, email: user.email },
        JWT_SECRET,
        { expiresIn: '7d' }
      );

      res.json({
        success: true,
        token,
        userId: user.id,
        provider: user.provider,
        email: user.email
      });
    } catch (error) {
      logger.error('Test login error', { error });
      res.status(500).json({ success: false, error: 'Test login failed' });
    }
  });

  // Seed database endpoint (BETA TESTING ONLY)
  app.post('/auth/seed-test-users', async (req: Request, res: Response) => {
    try {
      // Inline seed SQL to ensure it's available in deployment
      const seedSQL = `
-- Test Users
INSERT INTO users (id, provider, email, created_at, updated_at) VALUES
('google_test001', 'google', 'alex.chen@test.com', NOW() - INTERVAL '30 days', NOW() - INTERVAL '30 days'),
('google_test002', 'google', 'jordan.rivera@test.com', NOW() - INTERVAL '28 days', NOW() - INTERVAL '28 days'),
('google_test003', 'google', 'sam.patel@test.com', NOW() - INTERVAL '25 days', NOW() - INTERVAL '25 days'),
('google_test004', 'google', 'taylor.kim@test.com', NOW() - INTERVAL '22 days', NOW() - INTERVAL '22 days'),
('google_test005', 'google', 'morgan.santos@test.com', NOW() - INTERVAL '20 days', NOW() - INTERVAL '20 days'),
('google_test006', 'google', 'casey.nguyen@test.com', NOW() - INTERVAL '18 days', NOW() - INTERVAL '18 days'),
('google_test007', 'google', 'riley.anderson@test.com', NOW() - INTERVAL '15 days', NOW() - INTERVAL '15 days'),
('google_test008', 'google', 'avery.williams@test.com', NOW() - INTERVAL '12 days', NOW() - INTERVAL '12 days'),
('google_test009', 'google', 'drew.martinez@test.com', NOW() - INTERVAL '10 days', NOW() - INTERVAL '10 days'),
('google_test010', 'google', 'charlie.lee@test.com', NOW() - INTERVAL '8 days', NOW() - INTERVAL '8 days'),
('google_test011', 'google', 'jamie.brown@test.com', NOW() - INTERVAL '6 days', NOW() - INTERVAL '6 days'),
('google_test012', 'google', 'quinn.davis@test.com', NOW() - INTERVAL '5 days', NOW() - INTERVAL '5 days'),
('google_test013', 'google', 'reese.garcia@test.com', NOW() - INTERVAL '4 days', NOW() - INTERVAL '4 days'),
('google_test014', 'google', 'skylar.wilson@test.com', NOW() - INTERVAL '3 days', NOW() - INTERVAL '3 days'),
('google_test015', 'google', 'blake.moore@test.com', NOW() - INTERVAL '2 days', NOW() - INTERVAL '2 days'),
('google_test016', 'google', 'phoenix.taylor@test.com', NOW() - INTERVAL '1 days', NOW() - INTERVAL '1 days'),
('google_test017', 'google', 'sage.jackson@test.com', NOW() - INTERVAL '12 hours', NOW() - INTERVAL '12 hours'),
('google_test018', 'google', 'dakota.white@test.com', NOW() - INTERVAL '6 hours', NOW() - INTERVAL '6 hours'),
('google_test019', 'google', 'river.harris@test.com', NOW() - INTERVAL '3 hours', NOW() - INTERVAL '3 hours'),
('google_test020', 'google', 'ocean.clark@test.com', NOW() - INTERVAL '1 hour', NOW() - INTERVAL '1 hour')
ON CONFLICT (id) DO NOTHING;
      `;

      await pool.query(seedSQL);

      res.json({ success: true, message: 'Test users seeded successfully' });
      logger.info('Test users seeded');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      logger.error('Seed error', { error: errorMessage, fullError: error });
      res.status(500).json({ success: false, error: `Seed failed: ${errorMessage}` });
    }
  });

  logger.warn('Test login endpoint enabled (NOT FOR PRODUCTION)');
}

// Sentry error handler - must be after all routes but before generic error handler
if (process.env.SENTRY_DSN) {
  Sentry.setupExpressErrorHandler(app);
}

// Generic error handler (optional - for catching any remaining errors)
app.use((err: any, req: Request, res: Response, next: any) => {
  logger.error('Unhandled error', {
    error: err.message,
    stack: err.stack,
    path: req.path,
    method: req.method
  });
  res.status(500).json({ success: false, error: 'Internal server error' });
});

// Only start server if not in test environment
if (process.env.NODE_ENV !== 'test') {
  app.listen(PORT, () => {
    logger.info(`Auth service started`, { port: PORT, environment: process.env.NODE_ENV || 'development' });
  });
}

// Export for testing
export default app;
