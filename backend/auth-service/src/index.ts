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

import express, { Request, Response, NextFunction } from 'express';
import cors from 'cors';
import helmet from 'helmet';
import jwt from 'jsonwebtoken';
import { Pool } from 'pg';
import { OAuth2Client } from 'google-auth-library';
import appleSignin from 'apple-signin-auth';
import logger from './utils/logger';
import { authLimiter, verifyLimiter, generalLimiter } from './middleware/rate-limiter';
import { generateVerificationToken, generateResetToken, generateRefreshToken, hashToken, isTokenExpired } from './utils/crypto';
import { validatePassword, hashPassword, verifyPassword } from './utils/password';
import { emailService } from './services/email-service';
import { validateInputMiddleware, validateEmail, validateUserId, validateArray } from './utils/input-validation';
import { globalErrorHandler, notFoundHandler, asyncHandler, AppError, ErrorResponses } from './middleware/error-handler';
import { initializeSwagger } from './docs/swagger';
import cacheManager from './utils/cache-manager';

const app = express();
const PORT = process.env.PORT || 3001;

// Trust proxy - required for Railway/production environments behind reverse proxy
// This allows express-rate-limit to correctly identify users via X-Forwarded-For
app.set('trust proxy', 1);

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
// Critical security fix: Remove fallback to prevent secret exposure
if (!process.env.JWT_SECRET) {
  logger.error('JWT_SECRET environment variable is required and was not provided');
  process.exit(1);
}
const JWT_SECRET = process.env.JWT_SECRET;

// Token expiration configuration
// Access tokens are short-lived for security, refresh tokens are long-lived
const ACCESS_TOKEN_EXPIRY = '15m'; // 15 minutes - short-lived for security
const REFRESH_TOKEN_EXPIRY_MS = 7 * 24 * 60 * 60 * 1000; // 7 days in milliseconds

// Admin API key for test endpoints (required in production if ENABLE_TEST_ENDPOINTS=true)
const TEST_ENDPOINTS_API_KEY = process.env.TEST_ENDPOINTS_API_KEY;

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
    ? { rejectUnauthorized: false }
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

/**
 * Helper function to issue access token and refresh token pair
 * Stores refresh token hash in database for revocation support
 */
async function issueTokenPair(
  userId: string,
  provider: string,
  email: string,
  req: Request
): Promise<{ accessToken: string; refreshToken: string; expiresIn: number }> {
  // Generate short-lived access token
  const accessToken = jwt.sign(
    { userId, provider, email },
    JWT_SECRET,
    { expiresIn: ACCESS_TOKEN_EXPIRY }
  );

  // Generate refresh token
  const { token: refreshToken, tokenHash, expires } = generateRefreshToken();

  // Store refresh token hash in database
  await pool.query(
    `INSERT INTO refresh_tokens (user_id, token_hash, expires_at, device_info, ip_address)
     VALUES ($1, $2, $3, $4, $5)`,
    [
      userId,
      tokenHash,
      expires,
      req.headers['user-agent']?.substring(0, 500) || null,
      req.ip || req.socket.remoteAddress || null
    ]
  );

  logger.info('Token pair issued', { userId, provider });

  return {
    accessToken,
    refreshToken,
    expiresIn: 15 * 60 // 15 minutes in seconds
  };
}

/**
 * Middleware to verify admin API key for sensitive test endpoints
 */
function requireTestEndpointAuth(req: Request, res: Response, next: NextFunction) {
  // In non-production without ENABLE_TEST_ENDPOINTS, still allow access for dev convenience
  if (process.env.NODE_ENV !== 'production' && !TEST_ENDPOINTS_API_KEY) {
    return next();
  }

  // In production or when API key is configured, require it
  const providedKey = req.headers['x-admin-api-key'] as string;

  if (!TEST_ENDPOINTS_API_KEY) {
    logger.error('TEST_ENDPOINTS_API_KEY not configured but test endpoints enabled in production');
    return res.status(503).json({
      success: false,
      error: 'Test endpoints not properly configured'
    });
  }

  if (!providedKey || providedKey !== TEST_ENDPOINTS_API_KEY) {
    logger.warn('Unauthorized test endpoint access attempt', {
      ip: req.ip,
      path: req.path
    });
    return res.status(403).json({
      success: false,
      error: 'Forbidden: Invalid or missing admin API key'
    });
  }

  next();
}

// Security middleware
app.use(helmet({
  hidePoweredBy: true // Explicitly hide X-Powered-By header
}));
app.use(cors({
  origin: CORS_ORIGIN,
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization']
}));
app.use(express.json({ limit: '10kb' }));

// Health check endpoint
app.get('/health', (req: Request, res: Response) => {
  res.json({ status: 'ok', service: 'auth-service' });
});

// Apply input validation middleware to all routes
app.use(validateInputMiddleware);

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
      // Critical security fix: Require Apple CLIENT_ID, don't use fallback
      if (!process.env.APPLE_CLIENT_ID) {
        logger.error('APPLE_CLIENT_ID environment variable is required for Apple Sign-In');
        return res.status(503).json({ success: false, error: 'Apple Sign-In not configured' });
      }

      const appleIdTokenClaims = await appleSignin.verifyIdToken(identityToken, {
        // Audience validation with required environment variable
        audience: process.env.APPLE_CLIENT_ID,
        nonce: 'nonce' // Optional: verify nonce if you passed one during sign-in
      });

      if (!appleIdTokenClaims || !appleIdTokenClaims.sub) {
        return res.status(401).json({ success: false, error: 'Invalid identity token claims' });
      }

      const providerId = `apple_${appleIdTokenClaims.sub}`;
      const email = appleIdTokenClaims.email?.toLowerCase() || `user_${appleIdTokenClaims.sub}@apple.example.com`;
      const provider = 'apple';

      // Check if this Apple account is already linked
      const existingCredential = await pool.query(
        `SELECT ac.user_id FROM auth_credentials ac WHERE ac.provider = $1 AND ac.provider_id = $2`,
        [provider, providerId]
      );

      let userId: string;

      if (existingCredential.rows.length > 0) {
        userId = existingCredential.rows[0].user_id;
        await pool.query('UPDATE users SET updated_at = NOW() WHERE id = $1', [userId]);
      } else {
        // Check for existing user with same email (account linking)
        const existingEmail = await pool.query(
          'SELECT user_id FROM auth_credentials WHERE email = $1',
          [email]
        );

        const client = await pool.connect();
        try {
          await client.query('BEGIN');

          if (existingEmail.rows.length > 0) {
            // Link to existing account
            userId = existingEmail.rows[0].user_id;

            await client.query(
              `INSERT INTO auth_credentials (user_id, provider, provider_id, email, email_verified)
               VALUES ($1, $2, $3, $4, true)
               ON CONFLICT (provider, provider_id) DO UPDATE SET updated_at = NOW()`,
              [userId, provider, providerId, email]
            );
          } else {
            // Create new user (maintain backwards compatibility with old ID format)
            userId = providerId;

            await client.query(
              `INSERT INTO users (id, provider, email) VALUES ($1, $2, $3)
               ON CONFLICT (id) DO UPDATE SET updated_at = NOW(), email = $3`,
              [userId, provider, email]
            );

            await client.query(
              `INSERT INTO auth_credentials (user_id, provider, provider_id, email, email_verified)
               VALUES ($1, $2, $3, $4, true)
               ON CONFLICT (provider, provider_id) DO UPDATE SET updated_at = NOW()`,
              [userId, provider, providerId, email]
            );
          }

          await client.query('COMMIT');
        } catch (err) {
          await client.query('ROLLBACK');
          throw err;
        } finally {
          client.release();
        }
      }

      // Issue short-lived access token + refresh token pair
      const { accessToken, refreshToken, expiresIn } = await issueTokenPair(userId, provider, email, req);

      res.json({
        success: true,
        token: accessToken, // For backwards compatibility
        accessToken,
        refreshToken,
        expiresIn,
        userId,
        provider
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

    const ticket = await googleClient.verifyIdToken({
      idToken: idToken,
      audience: process.env.GOOGLE_CLIENT_ID,
    });

    const payload = ticket.getPayload();
    if (!payload || !payload.sub) {
      return res.status(401).json({ success: false, error: 'Invalid token payload' });
    }

    const providerId = `google_${payload.sub}`;
    const email = payload.email?.toLowerCase() || `user_${payload.sub}@google.example.com`;
    const provider = 'google';

    // Check if this Google account is already linked
    const existingCredential = await pool.query(
      `SELECT ac.user_id FROM auth_credentials ac WHERE ac.provider = $1 AND ac.provider_id = $2`,
      [provider, providerId]
    );

    let userId: string;

    if (existingCredential.rows.length > 0) {
      userId = existingCredential.rows[0].user_id;
      await pool.query('UPDATE users SET updated_at = NOW() WHERE id = $1', [userId]);
    } else {
      // Check for existing user with same email (account linking)
      const existingEmail = await pool.query(
        'SELECT user_id FROM auth_credentials WHERE email = $1',
        [email]
      );

      const client = await pool.connect();
      try {
        await client.query('BEGIN');

        if (existingEmail.rows.length > 0) {
          // Link to existing account
          userId = existingEmail.rows[0].user_id;

          await client.query(
            `INSERT INTO auth_credentials (user_id, provider, provider_id, email, email_verified)
             VALUES ($1, $2, $3, $4, true)
             ON CONFLICT (provider, provider_id) DO UPDATE SET updated_at = NOW()`,
            [userId, provider, providerId, email]
          );
        } else {
          // Create new user (maintain backwards compatibility with old ID format)
          userId = providerId;

          await client.query(
            `INSERT INTO users (id, provider, email) VALUES ($1, $2, $3)
             ON CONFLICT (id) DO UPDATE SET updated_at = NOW(), email = $3`,
            [userId, provider, email]
          );

          await client.query(
            `INSERT INTO auth_credentials (user_id, provider, provider_id, email, email_verified)
             VALUES ($1, $2, $3, $4, true)
             ON CONFLICT (provider, provider_id) DO UPDATE SET updated_at = NOW()`,
            [userId, provider, providerId, email]
          );
        }

        await client.query('COMMIT');
      } catch (err) {
        await client.query('ROLLBACK');
        throw err;
      } finally {
        client.release();
      }
    }

    // Issue short-lived access token + refresh token pair
    const { accessToken, refreshToken, expiresIn } = await issueTokenPair(userId, provider, email, req);

    res.json({
      success: true,
      token: accessToken, // For backwards compatibility
      accessToken,
      refreshToken,
      expiresIn,
      userId,
      provider
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

// Refresh token endpoint - Exchange a valid refresh token for a new access token
app.post('/auth/refresh', authLimiter, async (req: Request, res: Response) => {
  try {
    const { refreshToken } = req.body;

    if (!refreshToken) {
      return res.status(400).json({ success: false, error: 'Refresh token is required' });
    }

    // Hash the provided refresh token to look it up
    const tokenHash = hashToken(refreshToken);

    // Find the refresh token in the database
    const result = await pool.query(
      `SELECT rt.id, rt.user_id, rt.expires_at, rt.revoked_at, u.provider, u.email
       FROM refresh_tokens rt
       JOIN users u ON rt.user_id = u.id
       WHERE rt.token_hash = $1`,
      [tokenHash]
    );

    if (result.rows.length === 0) {
      logger.warn('Refresh attempt with unknown token', { ip: req.ip });
      return res.status(401).json({ success: false, error: 'Invalid refresh token' });
    }

    const tokenRecord = result.rows[0];

    // Check if token has been revoked
    if (tokenRecord.revoked_at) {
      logger.warn('Refresh attempt with revoked token', {
        userId: tokenRecord.user_id,
        ip: req.ip
      });
      return res.status(401).json({ success: false, error: 'Refresh token has been revoked' });
    }

    // Check if token has expired
    if (new Date() > new Date(tokenRecord.expires_at)) {
      logger.info('Refresh attempt with expired token', { userId: tokenRecord.user_id });
      return res.status(401).json({ success: false, error: 'Refresh token has expired' });
    }

    // Update last_used_at timestamp
    await pool.query(
      'UPDATE refresh_tokens SET last_used_at = NOW() WHERE id = $1',
      [tokenRecord.id]
    );

    // Generate new short-lived access token (keep same refresh token for now)
    // Note: For even stronger security, you could rotate refresh tokens here
    const accessToken = jwt.sign(
      { userId: tokenRecord.user_id, provider: tokenRecord.provider, email: tokenRecord.email },
      JWT_SECRET,
      { expiresIn: ACCESS_TOKEN_EXPIRY }
    );

    logger.info('Access token refreshed', { userId: tokenRecord.user_id });

    res.json({
      success: true,
      accessToken,
      expiresIn: 15 * 60 // 15 minutes in seconds
    });
  } catch (error) {
    logger.error('Token refresh error', { error });
    res.status(500).json({ success: false, error: 'Token refresh failed' });
  }
});

// Logout endpoint - Revoke refresh token
app.post('/auth/logout', authLimiter, async (req: Request, res: Response) => {
  try {
    const { refreshToken } = req.body;

    if (!refreshToken) {
      // If no refresh token provided, just acknowledge the logout
      // (client-side will clear access token)
      return res.json({ success: true, message: 'Logged out successfully' });
    }

    // Hash the provided refresh token
    const tokenHash = hashToken(refreshToken);

    // Revoke the refresh token
    const result = await pool.query(
      `UPDATE refresh_tokens
       SET revoked_at = NOW(), revoked_reason = 'logout'
       WHERE token_hash = $1 AND revoked_at IS NULL
       RETURNING user_id`,
      [tokenHash]
    );

    if (result.rows.length > 0) {
      logger.info('User logged out, refresh token revoked', { userId: result.rows[0].user_id });
    }

    res.json({ success: true, message: 'Logged out successfully' });
  } catch (error) {
    logger.error('Logout error', { error });
    res.status(500).json({ success: false, error: 'Logout failed' });
  }
});

// Logout from all devices - Revoke all refresh tokens for a user
app.post('/auth/logout-all', authLimiter, async (req: Request, res: Response) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ success: false, error: 'No token provided' });
    }

    const token = authHeader.substring(7);
    let decoded: any;
    try {
      decoded = jwt.verify(token, JWT_SECRET);
    } catch (err) {
      return res.status(401).json({ success: false, error: 'Invalid token' });
    }

    const userId = decoded.userId;

    // Revoke all active refresh tokens for this user
    const result = await pool.query(
      `UPDATE refresh_tokens
       SET revoked_at = NOW(), revoked_reason = 'logout_all'
       WHERE user_id = $1 AND revoked_at IS NULL
       RETURNING id`,
      [userId]
    );

    logger.info('User logged out from all devices', {
      userId,
      tokensRevoked: result.rows.length
    });

    res.json({
      success: true,
      message: 'Logged out from all devices',
      tokensRevoked: result.rows.length
    });
  } catch (error) {
    logger.error('Logout all error', { error });
    res.status(500).json({ success: false, error: 'Logout failed' });
  }
});

// Check subscription status endpoint
app.get('/auth/subscription-status', generalLimiter, async (req: Request, res: Response) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ success: false, error: 'No token provided' });
    }

    const token = authHeader.substring(7);
    let decoded: any;
    try {
      decoded = jwt.verify(token, JWT_SECRET);
    } catch (err) {
      return res.status(401).json({ success: false, error: 'Invalid token' });
    }

    const userId = decoded.userId;

    // Query user_subscriptions table for active subscription
    const result = await pool.query(
      `SELECT is_active, expires_at, product_id, entitlement_id
       FROM user_subscriptions
       WHERE user_id = $1
         AND is_active = true
         AND (expires_at IS NULL OR expires_at > NOW())
       ORDER BY expires_at DESC NULLS FIRST
       LIMIT 1`,
      [userId]
    );

    if (result.rows.length > 0) {
      const sub = result.rows[0];
      return res.json({
        success: true,
        isPremium: true,
        subscription: {
          productId: sub.product_id,
          entitlementId: sub.entitlement_id,
          expiresAt: sub.expires_at
        }
      });
    }

    res.json({
      success: true,
      isPremium: false,
      subscription: null
    });
  } catch (error) {
    logger.error('Error checking subscription status', { error });
    res.status(500).json({ success: false, error: 'Failed to check subscription status' });
  }
});

// Email registration endpoint
app.post('/auth/email/register', authLimiter, async (req: Request, res: Response) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({ success: false, error: 'Email and password are required' });
    }

    // Validate email format
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
      return res.status(400).json({ success: false, error: 'Invalid email format' });
    }

    // Validate password
    const passwordValidation = validatePassword(password);
    if (!passwordValidation.valid) {
      return res.status(400).json({
        success: false,
        error: 'Password does not meet requirements',
        details: passwordValidation.errors
      });
    }

    // Check if email already exists
    const existingUser = await pool.query(
      'SELECT user_id FROM auth_credentials WHERE email = $1',
      [email.toLowerCase()]
    );

    if (existingUser.rows.length > 0) {
      // Don't reveal that account exists - return same success message
      // but don't send verification email (user already has an account)
      logger.info('Registration attempted for existing email', { email: email.toLowerCase() });
      return res.json({
        success: true,
        message: 'Registration successful. Please check your email to verify your account.'
      });
    }

    // Generate user ID and hash password
    const userId = `email_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
    const passwordHash = await hashPassword(password);
    const { token: verificationToken, expires: verificationExpires } = generateVerificationToken();

    // Create user and auth credential in transaction
    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      // Create user
      await client.query(
        `INSERT INTO users (id, provider, email) VALUES ($1, $2, $3)`,
        [userId, 'email', email.toLowerCase()]
      );

      // Create auth credential
      await client.query(
        `INSERT INTO auth_credentials
         (user_id, provider, email, password_hash, email_verified, verification_token, verification_expires)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [userId, 'email', email.toLowerCase(), passwordHash, false, verificationToken, verificationExpires]
      );

      await client.query('COMMIT');
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }

    // Send verification email
    await emailService.sendVerificationEmail(email, verificationToken);

    logger.info('User registered', { userId, email: email.toLowerCase() });
    res.json({
      success: true,
      message: 'Registration successful. Please check your email to verify your account.'
    });
  } catch (error) {
    logger.error('Email registration error', { error });
    res.status(500).json({ success: false, error: 'Registration failed' });
  }
});

// Email verification endpoint
app.get('/auth/email/verify', verifyLimiter, async (req: Request, res: Response) => {
  try {
    const { token } = req.query;

    if (!token || typeof token !== 'string') {
      return res.status(400).json({ success: false, error: 'Verification token is required' });
    }

    // Find credential with this token
    const result = await pool.query(
      `SELECT user_id, email, verification_expires
       FROM auth_credentials
       WHERE verification_token = $1 AND provider = 'email'`,
      [token]
    );

    if (result.rows.length === 0) {
      return res.status(400).json({ success: false, error: 'Invalid or expired verification token' });
    }

    const credential = result.rows[0];

    // Check if token expired
    if (isTokenExpired(credential.verification_expires)) {
      return res.status(400).json({ success: false, error: 'Verification token has expired' });
    }

    // Mark as verified and clear token
    await pool.query(
      `UPDATE auth_credentials
       SET email_verified = true, verification_token = NULL, verification_expires = NULL, updated_at = NOW()
       WHERE user_id = $1 AND provider = 'email'`,
      [credential.user_id]
    );

    // Issue short-lived access token + refresh token pair for auto-login
    const { accessToken, refreshToken, expiresIn } = await issueTokenPair(
      credential.user_id,
      'email',
      credential.email,
      req
    );

    logger.info('Email verified', { userId: credential.user_id });
    res.json({
      success: true,
      message: 'Email verified successfully',
      token: accessToken, // For backwards compatibility
      accessToken,
      refreshToken,
      expiresIn,
      userId: credential.user_id
    });
  } catch (error) {
    logger.error('Email verification error', { error });
    res.status(500).json({ success: false, error: 'Verification failed' });
  }
});

// Email login endpoint
app.post('/auth/email/login', authLimiter, async (req: Request, res: Response) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({ success: false, error: 'Email and password are required' });
    }

    // Find credential
    const result = await pool.query(
      `SELECT ac.user_id, ac.email, ac.password_hash, ac.email_verified, u.provider
       FROM auth_credentials ac
       JOIN users u ON ac.user_id = u.id
       WHERE ac.email = $1 AND ac.provider = 'email'`,
      [email.toLowerCase()]
    );

    if (result.rows.length === 0) {
      return res.status(401).json({ success: false, error: 'Invalid email or password' });
    }

    const credential = result.rows[0];

    // Verify password
    const passwordValid = await verifyPassword(password, credential.password_hash);
    if (!passwordValid) {
      return res.status(401).json({ success: false, error: 'Invalid email or password' });
    }

    // Check if email is verified
    if (!credential.email_verified) {
      return res.status(403).json({
        success: false,
        error: 'Please verify your email before logging in',
        code: 'EMAIL_NOT_VERIFIED'
      });
    }

    await pool.query('UPDATE users SET updated_at = NOW() WHERE id = $1', [credential.user_id]);

    // Issue short-lived access token + refresh token pair
    const { accessToken, refreshToken, expiresIn } = await issueTokenPair(
      credential.user_id,
      'email',
      credential.email,
      req
    );

    logger.info('User logged in', { userId: credential.user_id, provider: 'email' });
    res.json({
      success: true,
      token: accessToken, // For backwards compatibility
      accessToken,
      refreshToken,
      expiresIn,
      userId: credential.user_id,
      provider: 'email'
    });
  } catch (error) {
    logger.error('Email login error', { error });
    res.status(500).json({ success: false, error: 'Login failed' });
  }
});

// Forgot password endpoint
app.post('/auth/email/forgot', authLimiter, async (req: Request, res: Response) => {
  try {
    const { email } = req.body;

    if (!email) {
      return res.status(400).json({ success: false, error: 'Email is required' });
    }

    // Always return success to prevent email enumeration
    const successResponse = {
      success: true,
      message: 'If an account exists with this email, a password reset link has been sent.'
    };

    const result = await pool.query(
      `SELECT user_id, email FROM auth_credentials WHERE email = $1 AND provider = 'email'`,
      [email.toLowerCase()]
    );

    if (result.rows.length === 0) {
      return res.json(successResponse);
    }

    const credential = result.rows[0];
    const { token: resetToken, expires: resetExpires } = generateResetToken();

    await pool.query(
      `UPDATE auth_credentials SET reset_token = $1, reset_expires = $2, updated_at = NOW()
       WHERE user_id = $3 AND provider = 'email'`,
      [resetToken, resetExpires, credential.user_id]
    );

    await emailService.sendPasswordResetEmail(credential.email, resetToken);

    logger.info('Password reset requested', { userId: credential.user_id });
    res.json(successResponse);
  } catch (error) {
    logger.error('Forgot password error', { error });
    res.status(500).json({ success: false, error: 'Request failed' });
  }
});

// Reset password endpoint
app.post('/auth/email/reset', authLimiter, async (req: Request, res: Response) => {
  try {
    const { token, newPassword } = req.body;

    if (!token || !newPassword) {
      return res.status(400).json({ success: false, error: 'Token and new password are required' });
    }

    const passwordValidation = validatePassword(newPassword);
    if (!passwordValidation.valid) {
      return res.status(400).json({
        success: false,
        error: 'Password does not meet requirements',
        details: passwordValidation.errors
      });
    }

    const result = await pool.query(
      `SELECT user_id, reset_expires FROM auth_credentials WHERE reset_token = $1 AND provider = 'email'`,
      [token]
    );

    if (result.rows.length === 0) {
      return res.status(400).json({ success: false, error: 'Invalid or expired reset token' });
    }

    const credential = result.rows[0];

    if (isTokenExpired(credential.reset_expires)) {
      return res.status(400).json({ success: false, error: 'Reset token has expired' });
    }

    const passwordHash = await hashPassword(newPassword);
    await pool.query(
      `UPDATE auth_credentials SET password_hash = $1, reset_token = NULL, reset_expires = NULL, updated_at = NOW()
       WHERE user_id = $2 AND provider = 'email'`,
      [passwordHash, credential.user_id]
    );

    logger.info('Password reset successful', { userId: credential.user_id });
    res.json({ success: true, message: 'Password has been reset successfully' });
  } catch (error) {
    logger.error('Reset password error', { error });
    res.status(500).json({ success: false, error: 'Reset failed' });
  }
});

// Resend verification email endpoint
app.post('/auth/email/resend-verification', authLimiter, async (req: Request, res: Response) => {
  try {
    const { email } = req.body;

    if (!email) {
      return res.status(400).json({ success: false, error: 'Email is required' });
    }

    const result = await pool.query(
      `SELECT user_id, email, email_verified FROM auth_credentials WHERE email = $1 AND provider = 'email'`,
      [email.toLowerCase()]
    );

    if (result.rows.length === 0) {
      return res.json({ success: true, message: 'If the account exists and is unverified, a verification email has been sent.' });
    }

    const credential = result.rows[0];

    if (credential.email_verified) {
      // Don't reveal verification status
      return res.json({ success: true, message: 'If the account exists and is unverified, a verification email has been sent.' });
    }

    const { token: verificationToken, expires: verificationExpires } = generateVerificationToken();

    await pool.query(
      `UPDATE auth_credentials SET verification_token = $1, verification_expires = $2, updated_at = NOW()
       WHERE user_id = $3 AND provider = 'email'`,
      [verificationToken, verificationExpires, credential.user_id]
    );

    await emailService.sendVerificationEmail(credential.email, verificationToken);

    logger.info('Verification email resent', { userId: credential.user_id });
    res.json({ success: true, message: 'Verification email has been sent.' });
  } catch (error) {
    logger.error('Resend verification error', { error });
    res.status(500).json({ success: false, error: 'Failed to resend verification email' });
  }
});

// Instagram OAuth endpoint
app.post('/auth/instagram', authLimiter, async (req: Request, res: Response) => {
  try {
    // Support both authorization code (preferred) and direct access token
    const { code, accessToken: providedToken } = req.body;

    if (!code && !providedToken) {
      return res.status(400).json({ success: false, error: 'Authorization code or access token is required' });
    }

    let accessToken = providedToken;

    // If authorization code is provided, exchange it for access token
    if (code) {
      const clientId = process.env.INSTAGRAM_CLIENT_ID;
      const clientSecret = process.env.INSTAGRAM_CLIENT_SECRET;
      const redirectUri = process.env.INSTAGRAM_REDIRECT_URI || 'https://getvlvt.vip/auth/instagram/callback';

      if (!clientId || !clientSecret) {
        logger.error('Instagram OAuth not configured: missing INSTAGRAM_CLIENT_ID or INSTAGRAM_CLIENT_SECRET');
        return res.status(500).json({ success: false, error: 'Instagram authentication not configured' });
      }

      // Exchange authorization code for access token
      const tokenResponse = await fetch('https://api.instagram.com/oauth/access_token', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams({
          client_id: clientId,
          client_secret: clientSecret,
          grant_type: 'authorization_code',
          redirect_uri: redirectUri,
          code: code,
        }),
      });

      if (!tokenResponse.ok) {
        const errorData = await tokenResponse.text();
        logger.error('Failed to exchange Instagram code for token', { error: errorData });
        return res.status(401).json({ success: false, error: 'Failed to authenticate with Instagram' });
      }

      const tokenData = await tokenResponse.json() as { access_token?: string };
      accessToken = tokenData.access_token;

      if (!accessToken) {
        return res.status(401).json({ success: false, error: 'No access token received from Instagram' });
      }
    }

    // Verify Instagram token and get user info
    const igResponse = await fetch(
      `https://graph.instagram.com/me?fields=id,username&access_token=${accessToken}`
    );

    if (!igResponse.ok) {
      return res.status(401).json({ success: false, error: 'Invalid Instagram access token' });
    }

    const igUser = await igResponse.json() as { id?: string; username?: string };

    if (!igUser.id) {
      return res.status(401).json({ success: false, error: 'Failed to get Instagram user info' });
    }

    const providerId = `instagram_${igUser.id}`;

    // Check if this Instagram account is already linked
    const existingCredential = await pool.query(
      `SELECT ac.user_id, ac.email, ac.email_verified, u.email as user_email
       FROM auth_credentials ac
       JOIN users u ON ac.user_id = u.id
       WHERE ac.provider = 'instagram' AND ac.provider_id = $1`,
      [providerId]
    );

    if (existingCredential.rows.length > 0) {
      const credential = existingCredential.rows[0];

      // If they have a verified email, log them in
      if (credential.email && credential.email_verified) {
        // Issue short-lived access token + refresh token pair
        const { accessToken, refreshToken, expiresIn } = await issueTokenPair(
          credential.user_id,
          'instagram',
          credential.email,
          req
        );

        return res.json({
          success: true,
          token: accessToken, // For backwards compatibility
          accessToken,
          refreshToken,
          expiresIn,
          userId: credential.user_id,
          provider: 'instagram'
        });
      } else {
        // Need to collect/verify email
        const tempToken = jwt.sign(
          { igUserId: igUser.id, igUsername: igUser.username, userId: credential.user_id },
          JWT_SECRET,
          { expiresIn: '15m' }
        );

        return res.json({
          success: true,
          needsEmail: true,
          tempToken,
          username: igUser.username
        });
      }
    }

    // New Instagram user - needs to provide email
    const tempToken = jwt.sign(
      { igUserId: igUser.id, igUsername: igUser.username, isNew: true },
      JWT_SECRET,
      { expiresIn: '15m' }
    );

    res.json({
      success: true,
      needsEmail: true,
      tempToken,
      username: igUser.username
    });
  } catch (error) {
    logger.error('Instagram authentication error', { error });
    res.status(500).json({ success: false, error: 'Authentication failed' });
  }
});

// Instagram complete registration (collect email)
app.post('/auth/instagram/complete', authLimiter, async (req: Request, res: Response) => {
  try {
    const { tempToken, email } = req.body;

    if (!tempToken || !email) {
      return res.status(400).json({ success: false, error: 'Temp token and email are required' });
    }

    // Validate email format
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
      return res.status(400).json({ success: false, error: 'Invalid email format' });
    }

    // Verify temp token
    let decoded: any;
    try {
      decoded = jwt.verify(tempToken, JWT_SECRET);
    } catch (err) {
      return res.status(401).json({ success: false, error: 'Invalid or expired token' });
    }

    const { igUserId, igUsername, userId: existingUserId, isNew } = decoded;
    const providerId = `instagram_${igUserId}`;
    const normalizedEmail = email.toLowerCase();

    // Check if email already exists (for account linking)
    const existingEmail = await pool.query(
      'SELECT user_id FROM auth_credentials WHERE email = $1',
      [normalizedEmail]
    );

    let userId: string;
    const { token: verificationToken, expires: verificationExpires } = generateVerificationToken();

    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      if (existingEmail.rows.length > 0) {
        // Link Instagram to existing account
        userId = existingEmail.rows[0].user_id;

        await client.query(
          `INSERT INTO auth_credentials
           (user_id, provider, provider_id, email, email_verified, verification_token, verification_expires)
           VALUES ($1, 'instagram', $2, $3, false, $4, $5)
           ON CONFLICT (provider, provider_id) DO UPDATE SET
             email = $3, verification_token = $4, verification_expires = $5, updated_at = NOW()`,
          [userId, providerId, normalizedEmail, verificationToken, verificationExpires]
        );
      } else if (existingUserId) {
        // Update existing Instagram credential with email
        userId = existingUserId;

        await client.query(
          `UPDATE auth_credentials
           SET email = $1, verification_token = $2, verification_expires = $3, updated_at = NOW()
           WHERE user_id = $4 AND provider = 'instagram'`,
          [normalizedEmail, verificationToken, verificationExpires, userId]
        );

        await client.query(
          'UPDATE users SET email = $1, updated_at = NOW() WHERE id = $2',
          [normalizedEmail, userId]
        );
      } else {
        // Create new user
        userId = `instagram_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;

        await client.query(
          'INSERT INTO users (id, provider, email) VALUES ($1, $2, $3)',
          [userId, 'instagram', normalizedEmail]
        );

        await client.query(
          `INSERT INTO auth_credentials
           (user_id, provider, provider_id, email, email_verified, verification_token, verification_expires)
           VALUES ($1, 'instagram', $2, $3, false, $4, $5)`,
          [userId, providerId, normalizedEmail, verificationToken, verificationExpires]
        );
      }

      await client.query('COMMIT');
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }

    // Send verification email
    await emailService.sendVerificationEmail(normalizedEmail, verificationToken);

    logger.info('Instagram registration completed', { userId, email: normalizedEmail });
    res.json({
      success: true,
      message: 'Please check your email to verify your account.',
      userId
    });
  } catch (error) {
    logger.error('Instagram complete error', { error });
    res.status(500).json({ success: false, error: 'Registration failed' });
  }
});

// Test login endpoint (ONLY FOR DEVELOPMENT/TESTING/BETA)
// This bypasses OAuth and allows direct login with any user ID
// Enable in beta testing with ENABLE_TEST_ENDPOINTS=true
// SECURITY: Protected by admin API key in production
if (process.env.NODE_ENV !== 'production' || process.env.ENABLE_TEST_ENDPOINTS === 'true') {
  // Log warning at startup if test endpoints are enabled
  if (process.env.NODE_ENV === 'production' && process.env.ENABLE_TEST_ENDPOINTS === 'true') {
    if (!TEST_ENDPOINTS_API_KEY) {
      logger.error('CRITICAL: Test endpoints enabled in production without TEST_ENDPOINTS_API_KEY!');
    } else {
      logger.warn('Test endpoints enabled in production (protected by admin API key)');
    }
  }

  app.post('/auth/test-login', requireTestEndpointAuth, async (req: Request, res: Response) => {
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

      // Issue short-lived access token + refresh token pair (same as regular auth)
      const { accessToken, refreshToken, expiresIn } = await issueTokenPair(
        user.id,
        user.provider,
        user.email,
        req
      );

      res.json({
        success: true,
        token: accessToken, // For backwards compatibility
        accessToken,
        refreshToken,
        expiresIn,
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
  // SECURITY: Protected by admin API key in production
  app.post('/auth/seed-test-users', requireTestEndpointAuth, async (req: Request, res: Response) => {
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

      // Grant premium to all test users
      const premiumSQL = `
INSERT INTO user_subscriptions (id, user_id, product_id, entitlement_id, is_active, will_renew, period_type, purchased_at, expires_at, store, environment)
SELECT
  'sub_' || id,
  id,
  'yearly',
  'No BS Dating Unlimited',
  true,
  true,
  'annual',
  NOW(),
  NOW() + INTERVAL '1 year',
  'test',
  'sandbox'
FROM users WHERE id LIKE 'google_test%'
ON CONFLICT (id) DO UPDATE SET is_active = true, expires_at = NOW() + INTERVAL '1 year';
      `;

      await pool.query(premiumSQL);

      res.json({ success: true, message: 'Test users seeded with premium access' });
      logger.info('Test users seeded with premium');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      logger.error('Seed error', { error: errorMessage, fullError: error });
      res.status(500).json({ success: false, error: `Seed failed: ${errorMessage}` });
    }
  });

  // Initialize database schema endpoint (BETA TESTING ONLY)
  // SECURITY: Protected by admin API key in production
  app.post('/auth/init-database', requireTestEndpointAuth, async (req: Request, res: Response) => {
    try {
      // Run each statement separately to handle existing tables gracefully
      const statements = [
        // Users table
        `CREATE TABLE IF NOT EXISTS users (
          id VARCHAR(255) PRIMARY KEY,
          provider VARCHAR(50) NOT NULL,
          email VARCHAR(255),
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )`,

        // Profiles table (basic)
        `CREATE TABLE IF NOT EXISTS profiles (
          user_id VARCHAR(255) PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
          name VARCHAR(255),
          age INTEGER,
          bio TEXT,
          photos TEXT[],
          interests TEXT[],
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )`,

        // Add location columns if missing
        `ALTER TABLE profiles ADD COLUMN IF NOT EXISTS latitude DECIMAL(10, 8)`,
        `ALTER TABLE profiles ADD COLUMN IF NOT EXISTS longitude DECIMAL(11, 8)`,
        `ALTER TABLE profiles ADD COLUMN IF NOT EXISTS location_updated_at TIMESTAMP WITH TIME ZONE`,

        // Matches table
        `CREATE TABLE IF NOT EXISTS matches (
          id VARCHAR(255) PRIMARY KEY,
          user_id_1 VARCHAR(255) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          user_id_2 VARCHAR(255) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          UNIQUE(user_id_1, user_id_2)
        )`,

        // Messages table
        `CREATE TABLE IF NOT EXISTS messages (
          id VARCHAR(255) PRIMARY KEY,
          match_id VARCHAR(255) NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
          sender_id VARCHAR(255) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          text TEXT NOT NULL,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )`,

        // Add message columns if missing
        `ALTER TABLE messages ADD COLUMN IF NOT EXISTS status VARCHAR(20) DEFAULT 'sent'`,
        `ALTER TABLE messages ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMP WITH TIME ZONE`,
        `ALTER TABLE messages ADD COLUMN IF NOT EXISTS read_at TIMESTAMP WITH TIME ZONE`,

        // Blocks table
        `CREATE TABLE IF NOT EXISTS blocks (
          id VARCHAR(255) PRIMARY KEY,
          user_id VARCHAR(255) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          blocked_user_id VARCHAR(255) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
          UNIQUE(user_id, blocked_user_id)
        )`,
        `ALTER TABLE blocks ADD COLUMN IF NOT EXISTS reason TEXT`,

        // Reports table
        `CREATE TABLE IF NOT EXISTS reports (
          id VARCHAR(255) PRIMARY KEY,
          reporter_id VARCHAR(255) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          reported_user_id VARCHAR(255) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          reason VARCHAR(100) NOT NULL,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
        )`,
        `ALTER TABLE reports ADD COLUMN IF NOT EXISTS details TEXT`,
        `ALTER TABLE reports ADD COLUMN IF NOT EXISTS status VARCHAR(50) DEFAULT 'pending'`,
        `ALTER TABLE reports ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP`,
        `ALTER TABLE reports ADD COLUMN IF NOT EXISTS reviewed_by VARCHAR(255)`,
        `ALTER TABLE reports ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMP WITH TIME ZONE`,
        `ALTER TABLE reports ADD COLUMN IF NOT EXISTS resolution_notes TEXT`,

        // Read receipts table
        `CREATE TABLE IF NOT EXISTS read_receipts (
          message_id VARCHAR(255) NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
          user_id VARCHAR(255) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          read_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (message_id, user_id)
        )`,

        // FCM tokens table
        `CREATE TABLE IF NOT EXISTS fcm_tokens (
          id SERIAL PRIMARY KEY,
          user_id VARCHAR(255) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          token TEXT NOT NULL,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
          UNIQUE(user_id, token)
        )`,
        `ALTER TABLE fcm_tokens ADD COLUMN IF NOT EXISTS device_type VARCHAR(20)`,
        `ALTER TABLE fcm_tokens ADD COLUMN IF NOT EXISTS device_id VARCHAR(255)`,
        `ALTER TABLE fcm_tokens ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true`,
        `ALTER TABLE fcm_tokens ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP`,
        `ALTER TABLE fcm_tokens ADD COLUMN IF NOT EXISTS last_used_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP`,

        // User status table
        `CREATE TABLE IF NOT EXISTS user_status (
          user_id VARCHAR(255) PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
          is_online BOOLEAN DEFAULT false,
          last_seen_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
        )`,
        `ALTER TABLE user_status ADD COLUMN IF NOT EXISTS socket_id VARCHAR(255)`,
        `ALTER TABLE user_status ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP`,

        // Typing indicators table
        `CREATE TABLE IF NOT EXISTS typing_indicators (
          match_id VARCHAR(255) NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
          user_id VARCHAR(255) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          is_typing BOOLEAN DEFAULT false,
          started_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (match_id, user_id)
        )`,

        // User subscriptions table (for RevenueCat webhook sync)
        `CREATE TABLE IF NOT EXISTS user_subscriptions (
          id VARCHAR(255) PRIMARY KEY,
          user_id VARCHAR(255) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          revenuecat_id VARCHAR(255),
          product_id VARCHAR(255) NOT NULL,
          entitlement_id VARCHAR(255),
          is_active BOOLEAN DEFAULT false,
          will_renew BOOLEAN DEFAULT true,
          period_type VARCHAR(50),
          purchased_at TIMESTAMP WITH TIME ZONE,
          expires_at TIMESTAMP WITH TIME ZONE,
          store VARCHAR(50),
          environment VARCHAR(50) DEFAULT 'production',
          created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
        )`,
        `CREATE INDEX IF NOT EXISTS idx_user_subscriptions_user_id ON user_subscriptions(user_id)`,
        `CREATE INDEX IF NOT EXISTS idx_user_subscriptions_active ON user_subscriptions(user_id, is_active)`,

        // Indexes
        `CREATE INDEX IF NOT EXISTS idx_profiles_location ON profiles(latitude, longitude)`,
        `CREATE INDEX IF NOT EXISTS idx_matches_user1 ON matches(user_id_1)`,
        `CREATE INDEX IF NOT EXISTS idx_matches_user2 ON matches(user_id_2)`,
        `CREATE INDEX IF NOT EXISTS idx_messages_match ON messages(match_id)`,
        `CREATE INDEX IF NOT EXISTS idx_messages_created ON messages(created_at)`,
        `CREATE INDEX IF NOT EXISTS idx_messages_status ON messages(status)`,
        `CREATE INDEX IF NOT EXISTS idx_blocks_user_id ON blocks(user_id)`,
        `CREATE INDEX IF NOT EXISTS idx_blocks_blocked_user_id ON blocks(blocked_user_id)`,
        `CREATE INDEX IF NOT EXISTS idx_reports_reported_user_id ON reports(reported_user_id)`,
        `CREATE INDEX IF NOT EXISTS idx_reports_status ON reports(status)`,
        `CREATE INDEX IF NOT EXISTS idx_read_receipts_user ON read_receipts(user_id)`,
        `CREATE INDEX IF NOT EXISTS idx_fcm_tokens_user ON fcm_tokens(user_id)`,
        `CREATE INDEX IF NOT EXISTS idx_fcm_tokens_active ON fcm_tokens(is_active)`,
        `CREATE INDEX IF NOT EXISTS idx_user_status_online ON user_status(is_online)`
      ];

      for (const sql of statements) {
        try {
          await pool.query(sql);
        } catch (err: any) {
          // Ignore "already exists" errors
          if (!err.message?.includes('already exists')) {
            throw err;
          }
        }
      }

      res.json({ success: true, message: 'Database schema initialized successfully' });
      logger.info('Database schema initialized');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      logger.error('Init database error', { error: errorMessage, fullError: error });
      res.status(500).json({ success: false, error: `Init failed: ${errorMessage}` });
    }
  });

  logger.warn('Test login endpoint enabled (NOT FOR PRODUCTION)');
}

// Async initialization function
async function initializeApp() {
  // Initialize advanced caching system
  try {
    await cacheManager.initialize();
    logger.info('Advanced caching system initialized');

    // Add cache health check endpoint
    app.get('/cache/health', async (req, res) => {
      const health = await cacheManager.healthCheck();
      res.json({
        success: true,
        cache: {
          healthy: health.healthy,
          message: health.message || 'Cache is operational'
        }
      });
    });
  } catch (error) {
    logger.warn('Cache initialization failed, continuing without cache', { error });
  }

  // Initialize Swagger API documentation
  if (process.env.NODE_ENV !== 'production' || process.env.ENABLE_SWAGGER === 'true') {
    initializeSwagger(app);
    logger.info('Swagger API documentation enabled');
  }

  // Sentry error handler - must be after all routes but before our global error handler
  if (process.env.SENTRY_DSN) {
    Sentry.setupExpressErrorHandler(app);
  }

  // Replace generic error handler with comprehensive error handling
  app.use(globalErrorHandler);

  // 404 handler for unmatched routes
  app.use(notFoundHandler);

  // Only start server if not in test environment
  if (process.env.NODE_ENV !== 'test') {
    app.listen(PORT, () => {
      logger.info(`Auth service started`, { port: PORT, environment: process.env.NODE_ENV || 'development' });
    });
  }
}

// Initialize the application
initializeApp().catch((error) => {
  logger.error('Failed to initialize application', { error });
  process.exit(1);
});

// Export for testing
export default app;
