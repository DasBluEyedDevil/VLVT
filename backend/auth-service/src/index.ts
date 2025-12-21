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
import logger from './utils/logger';
import { authLimiter, verifyLimiter, generalLimiter } from './middleware/rate-limiter';
import { generateVerificationToken, generateResetToken, generateRefreshToken, hashToken, isTokenExpired } from './utils/crypto';
import { validatePassword, hashPassword, verifyPassword } from './utils/password';
import { emailService } from './services/email-service';
import { validateInputMiddleware, validateEmail, validateUserId, validateArray } from './utils/input-validation';
import { globalErrorHandler, notFoundHandler, asyncHandler, AppError, ErrorResponses } from './middleware/error-handler';
import { initializeSwagger } from './docs/swagger';
import cacheManager from './utils/cache-manager';
import * as kycaidService from './services/kycaid-service';

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

// Security middleware with comprehensive headers
app.use(helmet({
  hidePoweredBy: true,
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'"],
      styleSrc: ["'self'", "'unsafe-inline'"],
      imgSrc: ["'self'", 'data:', 'https:'],
      connectSrc: ["'self'", 'https:'],
    },
  },
  hsts: {
    maxAge: 31536000, // 1 year
    includeSubDomains: true,
    preload: true,
  },
  frameguard: { action: 'deny' },
  noSniff: true,
  referrerPolicy: { policy: 'strict-origin-when-cross-origin' },
}));

// CORS configuration - require explicit origin in production
if (!CORS_ORIGIN && process.env.NODE_ENV === 'production') {
  logger.error('CORS_ORIGIN not configured in production');
  process.exit(1);
}
app.use(cors({
  origin: CORS_ORIGIN,
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-Admin-API-Key']
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

      // Extract nonce from the identity token for verification
      // The client should pass the nonce they used during sign-in
      const { nonce } = req.body;

      const appleIdTokenClaims = await appleSignin.verifyIdToken(identityToken, {
        // Audience validation with required environment variable
        audience: process.env.APPLE_CLIENT_ID,
        // Only verify nonce if client provided one (for backwards compatibility)
        ...(nonce && { nonce })
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
    const { email, password, inviteCode } = req.body;

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

    // Validate invite code if provided
    let referrerId: string | null = null;
    if (inviteCode) {
      const codeResult = await pool.query(
        `SELECT owner_id, used_by_id FROM invite_codes WHERE code = $1`,
        [inviteCode.toUpperCase()]
      );
      if (codeResult.rows.length === 0) {
        return res.status(400).json({ success: false, error: 'Invalid invite code' });
      }
      if (codeResult.rows[0].used_by_id) {
        return res.status(400).json({ success: false, error: 'Invite code has already been used' });
      }
      referrerId = codeResult.rows[0].owner_id;
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

      // Create user (with optional referred_by)
      await client.query(
        `INSERT INTO users (id, provider, email, referred_by) VALUES ($1, $2, $3, $4)`,
        [userId, 'email', email.toLowerCase(), referrerId]
      );

      // Create auth credential
      await client.query(
        `INSERT INTO auth_credentials
         (user_id, provider, email, password_hash, email_verified, verification_token, verification_expires)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [userId, 'email', email.toLowerCase(), passwordHash, false, verificationToken, verificationExpires]
      );

      // If invite code was used, mark it as used and award signup bonus
      if (inviteCode && referrerId) {
        await client.query(
          `UPDATE invite_codes SET used_by_id = $1, used_at = NOW() WHERE code = $2`,
          [userId, inviteCode.toUpperCase()]
        );

        // Award signup bonus ticket to new user
        await client.query(
          `INSERT INTO ticket_ledger (user_id, amount, reason, reference_id) VALUES ($1, 1, 'signup_bonus', $2)`,
          [userId, inviteCode.toUpperCase()]
        );

        logger.info('Invite code redeemed', { userId, inviteCode, referrerId });
      }

      await client.query('COMMIT');
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }

    // Send verification email
    await emailService.sendVerificationEmail(email, verificationToken);

    logger.info('User registered', { userId, email: email.toLowerCase(), inviteCode: inviteCode || null });
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

    // Award verification ticket (one-time)
    try {
      const existingVerificationTicket = await pool.query(
        `SELECT id FROM ticket_ledger WHERE user_id = $1 AND reason = 'verification'`,
        [credential.user_id]
      );
      if (existingVerificationTicket.rows.length === 0) {
        await awardTickets(credential.user_id, 1, 'verification', credential.user_id);
        logger.info('Awarded verification ticket', { userId: credential.user_id });
      }
    } catch (ticketError) {
      logger.error('Failed to award verification ticket', { error: ticketError, userId: credential.user_id });
      // Don't fail the verification if ticket awarding fails
    }

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
      // Add random delay to prevent timing attacks (100-300ms)
      await new Promise(resolve => setTimeout(resolve, 100 + Math.random() * 200));
      return res.json(successResponse);
    }

    const credential = result.rows[0];
    const { token: resetToken, tokenHash: resetTokenHash, expires: resetExpires } = generateResetToken();

    // SECURITY: Store hash of reset token, not the raw token
    await pool.query(
      `UPDATE auth_credentials SET reset_token = $1, reset_expires = $2, updated_at = NOW()
       WHERE user_id = $3 AND provider = 'email'`,
      [resetTokenHash, resetExpires, credential.user_id]
    );

    // Send the raw token via email - user will submit this, we'll hash it to compare
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

    // SECURITY: Hash the provided token to compare with stored hash
    const tokenHash = hashToken(token);

    const result = await pool.query(
      `SELECT user_id, reset_expires FROM auth_credentials WHERE reset_token = $1 AND provider = 'email'`,
      [tokenHash]
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
    // SECURITY: Only accept authorization codes, never direct access tokens
    // Direct token acceptance allows token injection attacks
    const { code } = req.body;

    if (!code) {
      return res.status(400).json({ success: false, error: 'Authorization code is required' });
    }

    let accessToken: string | undefined;

    // Exchange authorization code for access token
    {
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
    // Security: Use Authorization header instead of query parameter to avoid token exposure in logs
    const igResponse = await fetch(
      'https://graph.instagram.com/me?fields=id,username',
      {
        headers: {
          'Authorization': `Bearer ${accessToken}`
        }
      }
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

// ===== ACCOUNT DELETION ENDPOINT =====
// Required for Play Store compliance - allows users to delete their account

app.delete('/auth/account', generalLimiter, async (req: Request, res: Response) => {
  // Inline JWT verification (authenticateJWT is defined in middleware/auth.ts)
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ success: false, error: 'Authentication required' });
  }

  const token = authHeader.substring(7);
  let userId: string;

  try {
    const decoded = jwt.verify(token, JWT_SECRET) as { userId: string };
    userId = decoded.userId;
  } catch (error) {
    return res.status(401).json({ success: false, error: 'Invalid or expired token' });
  }

  const client = await pool.connect();

  try {
    logger.info('Account deletion requested', { userId });

    await client.query('BEGIN');

    // Delete user from users table - CASCADE will delete:
    // - profiles
    // - matches (as user_id_1 or user_id_2)
    // - messages (as sender_id)
    // - blocks (as user_id or blocked_user_id)
    // - reports (as reporter_id - reported_user reports are kept anonymized)
    // - auth_credentials
    // - refresh_tokens
    // - fcm_tokens
    // - user_status
    // - user_subscriptions
    // - swipes

    const result = await client.query(
      'DELETE FROM users WHERE id = $1 RETURNING id',
      [userId]
    );

    if (result.rowCount === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ success: false, error: 'Account not found' });
    }

    await client.query('COMMIT');

    logger.info('Account deleted successfully', { userId });

    res.json({
      success: true,
      message: 'Your account and all associated data have been permanently deleted.'
    });
  } catch (error) {
    await client.query('ROLLBACK');
    logger.error('Account deletion failed', { error, userId });
    res.status(500).json({ success: false, error: 'Failed to delete account' });
  } finally {
    client.release();
  }
});

// ===== GOLDEN TICKET ENDPOINTS =====
// Referral system for growth - users earn tickets through engagement

// Helper function to generate unique invite code
function generateInviteCode(): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Exclude similar chars: I,O,0,1
  let code = 'VLVT-';
  for (let i = 0; i < 4; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return code;
}

// Helper function to get ticket balance
async function getTicketBalance(userId: string): Promise<number> {
  const result = await pool.query(
    'SELECT COALESCE(SUM(amount), 0) as balance FROM ticket_ledger WHERE user_id = $1',
    [userId]
  );
  return parseInt(result.rows[0].balance) || 0;
}

// Helper function to award tickets
async function awardTickets(userId: string, amount: number, reason: string, referenceId?: string): Promise<void> {
  await pool.query(
    'INSERT INTO ticket_ledger (user_id, amount, reason, reference_id) VALUES ($1, $2, $3, $4)',
    [userId, amount, reason, referenceId || null]
  );
  logger.info('Tickets awarded', { userId, amount, reason, referenceId });
}

// GET /auth/tickets - Get user's ticket balance and history
app.get('/auth/tickets', generalLimiter, async (req: Request, res: Response) => {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ success: false, error: 'Authentication required' });
  }

  const token = authHeader.substring(7);
  let userId: string;

  try {
    const decoded = jwt.verify(token, JWT_SECRET) as { userId: string };
    userId = decoded.userId;
  } catch (error) {
    return res.status(401).json({ success: false, error: 'Invalid or expired token' });
  }

  try {
    // Get balance
    const balance = await getTicketBalance(userId);

    // Get invite codes created by this user
    const codesResult = await pool.query(
      `SELECT ic.code, ic.created_at, ic.used_at, ic.used_by_id,
              p.name as used_by_name
       FROM invite_codes ic
       LEFT JOIN profiles p ON p.user_id = ic.used_by_id
       WHERE ic.owner_id = $1
       ORDER BY ic.created_at DESC
       LIMIT 20`,
      [userId]
    );

    const codes = codesResult.rows.map(row => ({
      code: row.code,
      createdAt: row.created_at,
      used: row.used_by_id !== null,
      usedBy: row.used_by_name || null,
      usedAt: row.used_at,
    }));

    // Get ticket history
    const historyResult = await pool.query(
      `SELECT amount, reason, reference_id, created_at
       FROM ticket_ledger
       WHERE user_id = $1
       ORDER BY created_at DESC
       LIMIT 50`,
      [userId]
    );

    const history = historyResult.rows.map(row => ({
      amount: row.amount,
      reason: row.reason,
      referenceId: row.reference_id,
      createdAt: row.created_at,
    }));

    res.json({
      success: true,
      balance,
      codes,
      history,
    });
  } catch (error) {
    logger.error('Failed to get ticket balance', { error, userId });
    res.status(500).json({ success: false, error: 'Failed to get ticket balance' });
  }
});

// POST /auth/tickets/create-code - Generate a new invite code (costs 1 ticket)
app.post('/auth/tickets/create-code', generalLimiter, async (req: Request, res: Response) => {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ success: false, error: 'Authentication required' });
  }

  const token = authHeader.substring(7);
  let userId: string;

  try {
    const decoded = jwt.verify(token, JWT_SECRET) as { userId: string };
    userId = decoded.userId;
  } catch (error) {
    return res.status(401).json({ success: false, error: 'Invalid or expired token' });
  }

  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    // Check balance
    const balance = await getTicketBalance(userId);
    if (balance < 1) {
      await client.query('ROLLBACK');
      return res.status(400).json({
        success: false,
        error: 'Insufficient tickets',
        balance: balance,
      });
    }

    // Generate unique code (retry if collision)
    let code: string;
    let attempts = 0;
    const maxAttempts = 10;

    do {
      code = generateInviteCode();
      const existing = await client.query('SELECT 1 FROM invite_codes WHERE code = $1', [code]);
      if (existing.rowCount === 0) break;
      attempts++;
    } while (attempts < maxAttempts);

    if (attempts >= maxAttempts) {
      await client.query('ROLLBACK');
      return res.status(500).json({ success: false, error: 'Failed to generate unique code' });
    }

    // Create invite code
    await client.query(
      'INSERT INTO invite_codes (code, owner_id) VALUES ($1, $2)',
      [code, userId]
    );

    // Deduct ticket
    await client.query(
      'INSERT INTO ticket_ledger (user_id, amount, reason, reference_id) VALUES ($1, $2, $3, $4)',
      [userId, -1, 'invite_created', code]
    );

    await client.query('COMMIT');

    logger.info('Invite code created', { userId, code });

    res.json({
      success: true,
      code,
      shareUrl: `https://getvlvt.vip/invite/${code}`,
      balance: balance - 1,
    });
  } catch (error) {
    await client.query('ROLLBACK');
    logger.error('Failed to create invite code', { error, userId });
    res.status(500).json({ success: false, error: 'Failed to create invite code' });
  } finally {
    client.release();
  }
});

// POST /auth/tickets/validate - Validate invite code during signup
app.post('/auth/tickets/validate', authLimiter, async (req: Request, res: Response) => {
  const { code } = req.body;

  if (!code || typeof code !== 'string') {
    return res.status(400).json({ success: false, error: 'Invite code is required' });
  }

  const normalizedCode = code.toUpperCase().trim();

  try {
    const result = await pool.query(
      `SELECT ic.id, ic.owner_id, ic.used_by_id, ic.expires_at, p.name as owner_name
       FROM invite_codes ic
       LEFT JOIN profiles p ON p.user_id = ic.owner_id
       WHERE ic.code = $1`,
      [normalizedCode]
    );

    if (result.rowCount === 0) {
      return res.status(404).json({ success: false, error: 'Invalid invite code' });
    }

    const inviteCode = result.rows[0];

    // Check if already used
    if (inviteCode.used_by_id) {
      return res.status(400).json({ success: false, error: 'This invite code has already been used' });
    }

    // Check if expired
    if (inviteCode.expires_at && new Date(inviteCode.expires_at) < new Date()) {
      return res.status(400).json({ success: false, error: 'This invite code has expired' });
    }

    res.json({
      success: true,
      valid: true,
      invitedBy: inviteCode.owner_name || 'A VLVT member',
    });
  } catch (error) {
    logger.error('Failed to validate invite code', { error, code: normalizedCode });
    res.status(500).json({ success: false, error: 'Failed to validate invite code' });
  }
});

// POST /auth/tickets/redeem - Redeem invite code after signup (called internally or by client)
app.post('/auth/tickets/redeem', generalLimiter, async (req: Request, res: Response) => {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ success: false, error: 'Authentication required' });
  }

  const token = authHeader.substring(7);
  let userId: string;

  try {
    const decoded = jwt.verify(token, JWT_SECRET) as { userId: string };
    userId = decoded.userId;
  } catch (error) {
    return res.status(401).json({ success: false, error: 'Invalid or expired token' });
  }

  const { code } = req.body;

  if (!code || typeof code !== 'string') {
    return res.status(400).json({ success: false, error: 'Invite code is required' });
  }

  const normalizedCode = code.toUpperCase().trim();
  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    // Get invite code with lock
    const result = await client.query(
      `SELECT id, owner_id, used_by_id, expires_at
       FROM invite_codes
       WHERE code = $1
       FOR UPDATE`,
      [normalizedCode]
    );

    if (result.rowCount === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ success: false, error: 'Invalid invite code' });
    }

    const inviteCode = result.rows[0];

    // Check if already used
    if (inviteCode.used_by_id) {
      await client.query('ROLLBACK');
      return res.status(400).json({ success: false, error: 'This invite code has already been used' });
    }

    // Prevent self-redemption
    if (inviteCode.owner_id === userId) {
      await client.query('ROLLBACK');
      return res.status(400).json({ success: false, error: 'You cannot use your own invite code' });
    }

    // Check if expired
    if (inviteCode.expires_at && new Date(inviteCode.expires_at) < new Date()) {
      await client.query('ROLLBACK');
      return res.status(400).json({ success: false, error: 'This invite code has expired' });
    }

    // Mark code as used
    await client.query(
      'UPDATE invite_codes SET used_by_id = $1, used_at = NOW() WHERE id = $2',
      [userId, inviteCode.id]
    );

    // Update user's referred_by
    await client.query(
      'UPDATE users SET referred_by = $1 WHERE id = $2',
      [inviteCode.owner_id, userId]
    );

    // Award signup bonus ticket to new user
    await client.query(
      'INSERT INTO ticket_ledger (user_id, amount, reason, reference_id) VALUES ($1, $2, $3, $4)',
      [userId, 1, 'signup_bonus', normalizedCode]
    );

    await client.query('COMMIT');

    logger.info('Invite code redeemed', { userId, code: normalizedCode, ownerId: inviteCode.owner_id });

    res.json({
      success: true,
      message: 'Invite code redeemed successfully! You earned 1 ticket.',
      ticketsEarned: 1,
    });
  } catch (error) {
    await client.query('ROLLBACK');
    logger.error('Failed to redeem invite code', { error, userId, code: normalizedCode });
    res.status(500).json({ success: false, error: 'Failed to redeem invite code' });
  } finally {
    client.release();
  }
});

// Export helper for other services to award tickets
export { awardTickets, getTicketBalance };

// ===== KYCAID ID VERIFICATION ENDPOINTS =====
// Government ID verification via KYCAID - required before profile creation (Option B paywall)

// POST /auth/kycaid/start - Initiate ID verification process
app.post('/auth/kycaid/start', generalLimiter, async (req: Request, res: Response) => {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ success: false, error: 'Authentication required' });
  }

  const token = authHeader.substring(7);
  let userId: string;
  let email: string | undefined;

  try {
    const decoded = jwt.verify(token, JWT_SECRET) as { userId: string; email?: string };
    userId = decoded.userId;
    email = decoded.email;
  } catch (error) {
    return res.status(401).json({ success: false, error: 'Invalid or expired token' });
  }

  try {
    // Auto-verify test users (sandbox mode)
    const isTestUser = userId.startsWith('test_') || userId.startsWith('google_test');
    if (isTestUser) {
      // Check if already verified
      const existingResult = await pool.query(
        'SELECT id_verified FROM users WHERE id = $1',
        [userId]
      );

      if (existingResult.rows.length > 0 && existingResult.rows[0].id_verified) {
        return res.json({
          success: true,
          alreadyVerified: true,
          message: 'Your ID has already been verified'
        });
      }

      // Auto-verify test user
      await pool.query(
        'UPDATE users SET id_verified = true, id_verified_at = NOW() WHERE id = $1',
        [userId]
      );

      logger.info('Test user auto-verified for ID', { userId });

      return res.json({
        success: true,
        alreadyVerified: true,
        testMode: true,
        message: 'Test user automatically verified'
      });
    }

    // Check if KYCAID is configured (only needed for real users)
    if (!kycaidService.isKycaidConfigured()) {
      logger.error('KYCAID not configured');
      return res.status(503).json({ success: false, error: 'ID verification service not configured' });
    }

    // Check if user is already verified
    const userResult = await pool.query(
      'SELECT id_verified, kycaid_applicant_id FROM users WHERE id = $1',
      [userId]
    );

    if (userResult.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'User not found' });
    }

    const user = userResult.rows[0];

    if (user.id_verified) {
      return res.json({
        success: true,
        alreadyVerified: true,
        message: 'Your ID has already been verified'
      });
    }

    // Check for existing pending verification
    const pendingResult = await pool.query(
      `SELECT kycaid_verification_id FROM kycaid_verifications
       WHERE user_id = $1 AND status = 'pending'
       ORDER BY created_at DESC LIMIT 1`,
      [userId]
    );

    let applicantId = user.kycaid_applicant_id;
    let verificationId: string;

    // Create or get KYCAID applicant
    if (!applicantId) {
      const applicant = await kycaidService.createOrGetApplicant(userId, email);
      applicantId = applicant.applicant_id;

      // Store applicant ID on user
      await pool.query(
        'UPDATE users SET kycaid_applicant_id = $1 WHERE id = $2',
        [applicantId, userId]
      );
    }

    // Create verification if none pending, or return existing
    if (pendingResult.rows.length > 0) {
      verificationId = pendingResult.rows[0].kycaid_verification_id;
    } else {
      // Create new verification
      const callbackUrl = `${process.env.API_BASE_URL || 'https://auth-service-production.up.railway.app'}/auth/kycaid/webhook`;
      const verification = await kycaidService.createVerification(applicantId, callbackUrl);
      verificationId = verification.verification_id;

      // Store verification record
      await pool.query(
        `INSERT INTO kycaid_verifications
         (user_id, kycaid_applicant_id, kycaid_verification_id, kycaid_form_id, status)
         VALUES ($1, $2, $3, $4, 'pending')`,
        [userId, applicantId, verificationId, verification.form_id]
      );
    }

    logger.info('KYCAID verification started', { userId, applicantId, verificationId });

    // Return credentials for the mobile SDK
    res.json({
      success: true,
      verificationId,
      applicantId,
      formId: process.env.KYCAID_FORM_ID,
      // These are needed for the SDK initialization
      sdkConfig: {
        applicantId,
        verificationId,
        // SDK will use these to complete verification
      }
    });
  } catch (error) {
    logger.error('Failed to start KYCAID verification', { error, userId });
    res.status(500).json({ success: false, error: 'Failed to start ID verification' });
  }
});

// GET /auth/kycaid/status - Check verification status
app.get('/auth/kycaid/status', generalLimiter, async (req: Request, res: Response) => {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ success: false, error: 'Authentication required' });
  }

  const token = authHeader.substring(7);
  let userId: string;

  try {
    const decoded = jwt.verify(token, JWT_SECRET) as { userId: string };
    userId = decoded.userId;
  } catch (error) {
    return res.status(401).json({ success: false, error: 'Invalid or expired token' });
  }

  try {
    // Get user verification status
    const userResult = await pool.query(
      'SELECT id_verified, id_verified_at FROM users WHERE id = $1',
      [userId]
    );

    if (userResult.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'User not found' });
    }

    const user = userResult.rows[0];

    if (user.id_verified) {
      return res.json({
        success: true,
        verified: true,
        verifiedAt: user.id_verified_at
      });
    }

    // Get latest verification attempt
    const verificationResult = await pool.query(
      `SELECT kycaid_verification_id, status, verification_status,
              document_verified, face_match_verified, liveness_verified, aml_cleared,
              created_at, completed_at
       FROM kycaid_verifications
       WHERE user_id = $1
       ORDER BY created_at DESC LIMIT 1`,
      [userId]
    );

    if (verificationResult.rows.length === 0) {
      return res.json({
        success: true,
        verified: false,
        status: 'not_started',
        message: 'ID verification has not been started'
      });
    }

    const verification = verificationResult.rows[0];

    res.json({
      success: true,
      verified: false,
      status: verification.status,
      verificationStatus: verification.verification_status,
      checks: {
        document: verification.document_verified,
        faceMatch: verification.face_match_verified,
        liveness: verification.liveness_verified,
        aml: verification.aml_cleared
      },
      createdAt: verification.created_at,
      completedAt: verification.completed_at
    });
  } catch (error) {
    logger.error('Failed to get KYCAID status', { error, userId });
    res.status(500).json({ success: false, error: 'Failed to check verification status' });
  }
});

// POST /auth/kycaid/webhook - Receive KYCAID callbacks
// This endpoint does NOT require authentication - it receives callbacks from KYCAID
app.post('/auth/kycaid/webhook', express.raw({ type: 'application/json' }), async (req: Request, res: Response) => {
  try {
    // Verify signature
    const signature = req.headers['x-kycaid-signature'] as string;
    const rawBody = req.body;

    if (!signature || !kycaidService.verifyCallbackSignature(rawBody, signature)) {
      logger.warn('KYCAID webhook signature verification failed');
      return res.status(401).json({ success: false, error: 'Invalid signature' });
    }

    // Parse callback data
    const body = JSON.parse(rawBody.toString());
    const callbackData = kycaidService.parseCallbackData(body);

    if (!callbackData) {
      logger.warn('Invalid KYCAID callback data', { body });
      return res.status(400).json({ success: false, error: 'Invalid callback data' });
    }

    logger.info('KYCAID webhook received', {
      verificationId: callbackData.verification_id,
      applicantId: callbackData.applicant_id,
      status: callbackData.status,
      verificationStatus: callbackData.verification_status
    });

    // Find the verification record
    const verificationResult = await pool.query(
      `SELECT v.id, v.user_id FROM kycaid_verifications v
       WHERE v.kycaid_verification_id = $1`,
      [callbackData.verification_id]
    );

    if (verificationResult.rows.length === 0) {
      logger.warn('Verification not found for callback', { verificationId: callbackData.verification_id });
      // Return 200 to acknowledge receipt even if we can't process
      return res.json({ success: true, message: 'Acknowledged' });
    }

    const verification = verificationResult.rows[0];
    const userId = verification.user_id;

    // Extract verified user data
    const userData = kycaidService.extractVerifiedUserData(callbackData);

    // Determine status
    const isApproved = callbackData.verification_status === 'approved' && callbackData.verified;
    const status = isApproved ? 'approved' : (callbackData.verification_status === 'declined' ? 'declined' : 'completed');

    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      // Update verification record
      // Security: Encrypt sensitive PII data before storing
      const encryptionKey = process.env.KYCAID_ENCRYPTION_KEY;
      const piiData = {
        firstName: userData.firstName,
        lastName: userData.lastName,
        dateOfBirth: userData.dateOfBirth,
        documentNumber: userData.documentNumber,
        documentExpiry: userData.documentExpiry
      };

      if (encryptionKey) {
        // Store encrypted PII, clear plaintext columns
        await client.query(
          `UPDATE kycaid_verifications SET
             status = $1,
             verification_status = $2,
             encrypted_pii = encrypt_kycaid_pii($3::jsonb, $4),
             document_type = $5,
             document_country = $6,
             document_verified = $7,
             face_match_verified = $8,
             liveness_verified = $9,
             aml_cleared = $10,
             kycaid_response = $11,
             completed_at = NOW(),
             -- Clear plaintext PII columns
             first_name = NULL,
             last_name = NULL,
             date_of_birth = NULL,
             document_number = NULL,
             document_expiry = NULL
           WHERE id = $12`,
          [
            status,
            callbackData.verification_status,
            JSON.stringify(piiData),
            encryptionKey,
            userData.documentType,
            userData.documentCountry,
            userData.documentVerified,
            userData.faceMatchVerified,
            userData.livenessVerified,
            userData.amlCleared,
            JSON.stringify(body),
            verification.id
          ]
        );
      } else {
        // Fallback: Store in plaintext with warning (for backwards compatibility during migration)
        logger.warn('KYCAID_ENCRYPTION_KEY not set - storing PII in plaintext. THIS IS A SECURITY RISK.');
        await client.query(
          `UPDATE kycaid_verifications SET
             status = $1,
             verification_status = $2,
             first_name = $3,
             last_name = $4,
             date_of_birth = $5,
             document_type = $6,
             document_number = $7,
             document_country = $8,
             document_expiry = $9,
             document_verified = $10,
             face_match_verified = $11,
             liveness_verified = $12,
             aml_cleared = $13,
             kycaid_response = $14,
             completed_at = NOW()
           WHERE id = $15`,
          [
            status,
            callbackData.verification_status,
            userData.firstName,
            userData.lastName,
            userData.dateOfBirth,
            userData.documentType,
            userData.documentNumber,
            userData.documentCountry,
            userData.documentExpiry,
            userData.documentVerified,
            userData.faceMatchVerified,
            userData.livenessVerified,
            userData.amlCleared,
            JSON.stringify(body),
            verification.id
          ]
        );
      }

      // If approved, update user as verified
      if (isApproved) {
        await client.query(
          'UPDATE users SET id_verified = true, id_verified_at = NOW() WHERE id = $1',
          [userId]
        );

        // Award verification completion ticket (one-time)
        const existingTicket = await client.query(
          `SELECT id FROM ticket_ledger WHERE user_id = $1 AND reason = 'id_verification'`,
          [userId]
        );
        if (existingTicket.rows.length === 0) {
          await client.query(
            'INSERT INTO ticket_ledger (user_id, amount, reason, reference_id) VALUES ($1, $2, $3, $4)',
            [userId, 1, 'id_verification', callbackData.verification_id]
          );
        }

        logger.info('User ID verified', { userId, verificationId: callbackData.verification_id });
      } else if (status === 'declined') {
        logger.info('User ID verification declined', {
          userId,
          verificationId: callbackData.verification_id,
          reason: callbackData.verification_status
        });
      }

      await client.query('COMMIT');
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }

    res.json({ success: true, message: 'Webhook processed' });
  } catch (error) {
    logger.error('KYCAID webhook processing error', { error });
    // Return 200 to prevent retries for processing errors
    res.json({ success: true, message: 'Acknowledged with errors' });
  }
});

// GET /auth/kycaid/refresh - Manually refresh verification status from KYCAID
app.get('/auth/kycaid/refresh', generalLimiter, async (req: Request, res: Response) => {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ success: false, error: 'Authentication required' });
  }

  const token = authHeader.substring(7);
  let userId: string;

  try {
    const decoded = jwt.verify(token, JWT_SECRET) as { userId: string };
    userId = decoded.userId;
  } catch (error) {
    return res.status(401).json({ success: false, error: 'Invalid or expired token' });
  }

  try {
    // Get latest verification
    const verificationResult = await pool.query(
      `SELECT kycaid_verification_id, status FROM kycaid_verifications
       WHERE user_id = $1
       ORDER BY created_at DESC LIMIT 1`,
      [userId]
    );

    if (verificationResult.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'No verification found' });
    }

    const verificationId = verificationResult.rows[0].kycaid_verification_id;

    // Fetch current status from KYCAID
    const kycaidStatus = await kycaidService.getVerificationStatus(verificationId);

    logger.info('KYCAID status refreshed', { userId, verificationId, status: kycaidStatus.status });

    res.json({
      success: true,
      status: kycaidStatus.status,
      verificationStatus: kycaidStatus.verification_status
    });
  } catch (error) {
    logger.error('Failed to refresh KYCAID status', { error, userId });
    res.status(500).json({ success: false, error: 'Failed to refresh verification status' });
  }
});

// ===== REVENUECAT WEBHOOK =====
// Receives subscription events from RevenueCat to sync with database

const REVENUECAT_WEBHOOK_AUTH = process.env.REVENUECAT_WEBHOOK_AUTH;

app.post('/auth/revenuecat/webhook', express.json(), async (req: Request, res: Response) => {
  // Verify authorization header
  const authHeader = req.headers.authorization;

  if (REVENUECAT_WEBHOOK_AUTH) {
    if (!authHeader || authHeader !== REVENUECAT_WEBHOOK_AUTH) {
      logger.warn('RevenueCat webhook: Invalid or missing authorization header');
      return res.status(401).json({ success: false, error: 'Unauthorized' });
    }
  } else {
    logger.warn('RevenueCat webhook: REVENUECAT_WEBHOOK_AUTH not configured - accepting all requests');
  }

  try {
    const { api_version, event } = req.body;

    if (!event || !event.type) {
      logger.warn('RevenueCat webhook: Invalid payload - missing event or type');
      return res.status(400).json({ success: false, error: 'Invalid payload' });
    }

    const {
      type,
      id: eventId,
      app_user_id,
      original_app_user_id,
      product_id,
      entitlement_ids,
      period_type,
      purchased_at_ms,
      expiration_at_ms,
      store,
      environment,
      price,
      currency,
      transaction_id,
      original_transaction_id,
    } = event;

    // Use original_app_user_id as the primary identifier (most stable)
    const userId = original_app_user_id || app_user_id;

    if (!userId) {
      logger.warn('RevenueCat webhook: No user ID in event', { eventId, type });
      return res.status(400).json({ success: false, error: 'Missing user ID' });
    }

    logger.info('RevenueCat webhook received', {
      eventId,
      type,
      userId,
      productId: product_id,
      environment,
    });

    // Handle different event types
    switch (type) {
      case 'TEST':
        // Test webhook - just acknowledge
        logger.info('RevenueCat TEST webhook received');
        break;

      case 'INITIAL_PURCHASE':
      case 'RENEWAL':
      case 'UNCANCELLATION':
      case 'NON_RENEWING_PURCHASE': {
        // Active subscription - upsert into database
        const entitlementId = entitlement_ids?.[0] || 'premium';
        const purchasedAt = purchased_at_ms ? new Date(purchased_at_ms) : new Date();
        const expiresAt = expiration_at_ms ? new Date(expiration_at_ms) : null;

        await pool.query(
          `INSERT INTO user_subscriptions (
            id, user_id, revenuecat_id, product_id, entitlement_id,
            is_active, will_renew, period_type, purchased_at, expires_at,
            store, environment, created_at, updated_at
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, NOW(), NOW())
          ON CONFLICT (id) DO UPDATE SET
            is_active = $6,
            will_renew = $7,
            expires_at = $10,
            updated_at = NOW()`,
          [
            `rc_${original_transaction_id || transaction_id || eventId}`,
            userId,
            app_user_id,
            product_id,
            entitlementId,
            true, // is_active
            type !== 'NON_RENEWING_PURCHASE', // will_renew
            period_type || 'normal',
            purchasedAt,
            expiresAt,
            store || 'unknown',
            environment || 'production',
          ]
        );

        logger.info('RevenueCat subscription activated', {
          userId,
          productId: product_id,
          type,
          expiresAt,
        });
        break;
      }

      case 'CANCELLATION': {
        // User cancelled - will_renew = false, but still active until expiration
        await pool.query(
          `UPDATE user_subscriptions
           SET will_renew = false, updated_at = NOW()
           WHERE user_id = $1 AND is_active = true`,
          [userId]
        );

        logger.info('RevenueCat subscription cancelled (will expire)', { userId });
        break;
      }

      case 'EXPIRATION':
      case 'BILLING_ISSUE': {
        // Subscription expired or billing failed - deactivate
        const expiresAt = expiration_at_ms ? new Date(expiration_at_ms) : new Date();

        await pool.query(
          `UPDATE user_subscriptions
           SET is_active = false, will_renew = false, expires_at = $2, updated_at = NOW()
           WHERE user_id = $1`,
          [userId, expiresAt]
        );

        logger.info('RevenueCat subscription expired/deactivated', { userId, type });
        break;
      }

      case 'PRODUCT_CHANGE': {
        // User changed product - update product_id
        const entitlementId = entitlement_ids?.[0] || 'premium';
        const expiresAt = expiration_at_ms ? new Date(expiration_at_ms) : null;

        await pool.query(
          `UPDATE user_subscriptions
           SET product_id = $2, entitlement_id = $3, expires_at = $4, updated_at = NOW()
           WHERE user_id = $1 AND is_active = true`,
          [userId, product_id, entitlementId, expiresAt]
        );

        logger.info('RevenueCat product changed', { userId, productId: product_id });
        break;
      }

      case 'TRANSFER': {
        // Subscription transferred to different user
        const newUserId = app_user_id;
        if (newUserId && newUserId !== original_app_user_id) {
          await pool.query(
            `UPDATE user_subscriptions
             SET user_id = $2, updated_at = NOW()
             WHERE user_id = $1 AND is_active = true`,
            [original_app_user_id, newUserId]
          );
          logger.info('RevenueCat subscription transferred', {
            fromUser: original_app_user_id,
            toUser: newUserId,
          });
        }
        break;
      }

      default:
        // Log unknown events but don't fail
        logger.info('RevenueCat webhook: Unhandled event type', { type, eventId });
    }

    // Always return 200 to acknowledge receipt
    res.json({ success: true, message: 'Webhook processed' });

  } catch (error) {
    logger.error('RevenueCat webhook processing error', { error });
    // Return 200 anyway to prevent retries for processing errors
    // RevenueCat will keep retrying on non-2xx responses
    res.json({ success: true, message: 'Acknowledged with errors' });
  }
});

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
