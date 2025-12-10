import dotenv from 'dotenv';
// Load environment variables first
dotenv.config();

// Initialize Sentry before any other imports
import * as Sentry from '@sentry/node';

if (process.env.SENTRY_DSN) {
  Sentry.init({
    dsn: process.env.SENTRY_DSN,
    environment: process.env.NODE_ENV || 'development',
    tracesSampleRate: 0.1, // 10% of transactions
  });
}

import express, { Request, Response, NextFunction } from 'express';
import { createServer } from 'http';
import cors from 'cors';
import helmet from 'helmet';
import { Pool } from 'pg';
import { authMiddleware } from './middleware/auth';
import { validateMessage, validateMatch, validateReport, validateBlock } from './middleware/validation';
import logger from './utils/logger';
import { generalLimiter, matchLimiter, messageLimiter, reportLimiter } from './middleware/rate-limiter';
import { initializeSocketIO } from './socket';
import { initializeFirebase, registerFCMToken, unregisterFCMToken, sendMatchNotification } from './services/fcm-service';

// Admin API key for protected endpoints
const ADMIN_API_KEY = process.env.TEST_ENDPOINTS_API_KEY;

/**
 * Middleware to require admin API key for sensitive endpoints
 */
function requireAdminAuth(req: Request, res: Response, next: NextFunction) {
  // In non-production without API key, allow access for dev convenience
  if (process.env.NODE_ENV !== 'production' && !ADMIN_API_KEY) {
    return next();
  }

  const providedKey = req.headers['x-admin-api-key'] as string;

  if (!ADMIN_API_KEY) {
    logger.error('Admin API key not configured but admin endpoint accessed in production');
    return res.status(503).json({
      success: false,
      error: 'Admin endpoints not properly configured'
    });
  }

  if (!providedKey || providedKey !== ADMIN_API_KEY) {
    logger.warn('Unauthorized admin endpoint access attempt', {
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

const app = express();
const PORT = process.env.PORT || 3003;

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
if (!process.env.DATABASE_URL && process.env.NODE_ENV !== 'test') {
  logger.error('DATABASE_URL environment variable is required');
  process.exit(1);
}

if (!process.env.JWT_SECRET && process.env.NODE_ENV !== 'test') {
  logger.error('JWT_SECRET environment variable is required');
  process.exit(1);
}

// CORS origin from environment variable
const CORS_ORIGIN = process.env.CORS_ORIGIN || 'http://localhost:19006';

// Require explicit CORS origin in production
if (!process.env.CORS_ORIGIN && process.env.NODE_ENV === 'production') {
  logger.error('CORS_ORIGIN not configured in production');
  process.exit(1);
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
      connectSrc: ["'self'", 'wss:', 'https:'],
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
app.use(cors({
  origin: CORS_ORIGIN,
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization']
}));
app.use(express.json({ limit: '10kb' }));

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

// Initialize Firebase for push notifications
initializeFirebase();

// Health check endpoint
app.get('/health', (req: Request, res: Response) => {
  res.json({ status: 'ok', service: 'chat-service' });
});

// Get matches for a user - Only allow users to view their own matches
app.get('/matches/:userId', authMiddleware, generalLimiter, async (req: Request, res: Response) => {
  try {
    const requestedUserId = req.params.userId;
    const authenticatedUserId = req.user!.userId;

    // Authorization check: user can only view their own matches
    if (requestedUserId !== authenticatedUserId) {
      return res.status(403).json({
        success: false,
        error: 'Forbidden: Cannot access other users\' matches'
      });
    }

    const result = await pool.query(
      `SELECT id, user_id_1, user_id_2, created_at
       FROM matches
       WHERE user_id_1 = $1 OR user_id_2 = $1`,
      [requestedUserId]
    );

    const matches = result.rows.map(match => ({
      id: match.id,
      userId1: match.user_id_1,
      userId2: match.user_id_2,
      createdAt: match.created_at
    }));

    res.json({ success: true, matches });
  } catch (error) {
    logger.error('Failed to retrieve matches', { error, requestedUserId: req.params.userId });
    res.status(500).json({ success: false, error: 'Failed to retrieve matches' });
  }
});

// Create a match - Verify authenticated user is one of the participants
app.post('/matches', authMiddleware, matchLimiter, validateMatch, async (req: Request, res: Response) => {
  try {
    const authenticatedUserId = req.user!.userId;
    const { userId1, userId2 } = req.body;

    if (!userId1 || !userId2) {
      return res.status(400).json({ success: false, error: 'Both userIds are required' });
    }

    // Authorization check: authenticated user must be one of the match participants
    if (authenticatedUserId !== userId1 && authenticatedUserId !== userId2) {
      return res.status(403).json({
        success: false,
        error: 'Forbidden: Can only create matches involving yourself'
      });
    }

    // Ensure both users exist in the database (auto-create if needed for dev/test)
    // This handles the case where auth happens on Railway but chat service runs locally
    for (const uid of [userId1, userId2]) {
      const userExists = await pool.query('SELECT id FROM users WHERE id = $1', [uid]);
      if (userExists.rows.length === 0) {
        // Determine provider from userId format
        const provider = uid.startsWith('google_') ? 'google' : uid.startsWith('apple_') ? 'apple' : 'unknown';
        await pool.query(
          `INSERT INTO users (id, provider, email) VALUES ($1, $2, $3)
           ON CONFLICT (id) DO NOTHING`,
          [uid, provider, `${uid}@placeholder.local`]
        );
        logger.info('Auto-created user for match', { userId: uid, provider });
      }
    }

    // Check for existing match in both directions
    const existingMatch = await pool.query(
      `SELECT id, user_id_1, user_id_2, created_at
       FROM matches
       WHERE (user_id_1 = $1 AND user_id_2 = $2)
          OR (user_id_1 = $2 AND user_id_2 = $1)`,
      [userId1, userId2]
    );

    // If match already exists, return the existing match
    if (existingMatch.rows.length > 0) {
      const match = existingMatch.rows[0];
      return res.json({
        success: true,
        match: {
          id: match.id,
          userId1: match.user_id_1,
          userId2: match.user_id_2,
          createdAt: match.created_at
        },
        alreadyExists: true
      });
    }

    // Create new match only if it doesn't exist
    const matchId = `match_${Date.now()}`;

    const result = await pool.query(
      `INSERT INTO matches (id, user_id_1, user_id_2)
       VALUES ($1, $2, $3)
       RETURNING id, user_id_1, user_id_2, created_at`,
      [matchId, userId1, userId2]
    );

    const match = result.rows[0];

    // Send push notifications to both users about the match
    // Get user names for the notifications
    const profilesResult = await pool.query(
      'SELECT user_id, name FROM profiles WHERE user_id IN ($1, $2)',
      [userId1, userId2]
    );

    if (profilesResult.rows.length === 2) {
      const user1Profile = profilesResult.rows.find((p: any) => p.user_id === userId1);
      const user2Profile = profilesResult.rows.find((p: any) => p.user_id === userId2);

      if (user1Profile && user2Profile) {
        // Send notification to user1 about matching with user2 (don't await - fire and forget)
        sendMatchNotification(pool, userId1, user2Profile.name, matchId).catch(err =>
          logger.error('Failed to send match notification to user1', { userId: userId1, error: err })
        );

        // Send notification to user2 about matching with user1 (don't await - fire and forget)
        sendMatchNotification(pool, userId2, user1Profile.name, matchId).catch(err =>
          logger.error('Failed to send match notification to user2', { userId: userId2, error: err })
        );
      }
    }

    res.json({
      success: true,
      match: {
        id: match.id,
        userId1: match.user_id_1,
        userId2: match.user_id_2,
        createdAt: match.created_at
      }
    });
  } catch (error: any) {
    logger.error('Failed to create match', {
      error: error.message,
      stack: error.stack,
      code: error.code,
      detail: error.detail,
      authenticatedUserId: req.user?.userId,
      userId1: req.body.userId1,
      userId2: req.body.userId2
    });
    res.status(500).json({ success: false, error: 'Failed to create match' });
  }
});

// Get messages for a match - Verify user is part of the match
app.get('/messages/:matchId', authMiddleware, generalLimiter, async (req: Request, res: Response) => {
  try {
    const { matchId } = req.params;
    const authenticatedUserId = req.user!.userId;

    // Verify the user is part of this match
    const matchCheck = await pool.query(
      `SELECT id FROM matches
       WHERE id = $1 AND (user_id_1 = $2 OR user_id_2 = $2)`,
      [matchId, authenticatedUserId]
    );

    if (matchCheck.rows.length === 0) {
      return res.status(403).json({
        success: false,
        error: 'Forbidden: You are not part of this match'
      });
    }

    const result = await pool.query(
      `SELECT id, match_id, sender_id, text, created_at
       FROM messages
       WHERE match_id = $1
       ORDER BY created_at ASC`,
      [matchId]
    );

    const messages = result.rows.map(msg => ({
      id: msg.id,
      matchId: msg.match_id,
      senderId: msg.sender_id,
      text: msg.text,
      timestamp: msg.created_at
    }));

    res.json({ success: true, messages });
  } catch (error) {
    logger.error('Failed to retrieve messages', { error, matchId: req.params.matchId });
    res.status(500).json({ success: false, error: 'Failed to retrieve messages' });
  }
});

// Send a message - Verify senderId matches authenticated user and user is part of match
app.post('/messages', authMiddleware, messageLimiter, validateMessage, async (req: Request, res: Response) => {
  try {
    const authenticatedUserId = req.user!.userId;
    const { matchId, senderId, text } = req.body;

    if (!matchId || !senderId || !text) {
      return res.status(400).json({ success: false, error: 'matchId, senderId, and text are required' });
    }

    // Authorization check: senderId must match authenticated user
    if (senderId !== authenticatedUserId) {
      return res.status(403).json({
        success: false,
        error: 'Forbidden: Cannot send messages as another user'
      });
    }

    // Verify the user is part of this match
    const matchCheck = await pool.query(
      `SELECT id FROM matches
       WHERE id = $1 AND (user_id_1 = $2 OR user_id_2 = $2)`,
      [matchId, authenticatedUserId]
    );

    if (matchCheck.rows.length === 0) {
      return res.status(403).json({
        success: false,
        error: 'Forbidden: You are not part of this match'
      });
    }

    const messageId = `msg_${Date.now()}`;

    const result = await pool.query(
      `INSERT INTO messages (id, match_id, sender_id, text)
       VALUES ($1, $2, $3, $4)
       RETURNING id, match_id, sender_id, text, created_at`,
      [messageId, matchId, senderId, text]
    );

    const message = result.rows[0];

    res.json({
      success: true,
      message: {
        id: message.id,
        matchId: message.match_id,
        senderId: message.sender_id,
        text: message.text,
        timestamp: message.created_at
      }
    });
  } catch (error) {
    logger.error('Failed to send message', { error, matchId: req.body.matchId, senderId: req.user?.userId });
    res.status(500).json({ success: false, error: 'Failed to send message' });
  }
});

// Get unread message counts for all matches of a user - Only allow users to view their own unread counts
app.get('/matches/:userId/unread-counts', authMiddleware, generalLimiter, async (req: Request, res: Response) => {
  try {
    const requestedUserId = req.params.userId;
    const authenticatedUserId = req.user!.userId;

    // Authorization check: user can only view their own unread counts
    if (requestedUserId !== authenticatedUserId) {
      return res.status(403).json({
        success: false,
        error: 'Forbidden: Cannot access other users\' unread counts'
      });
    }

    // Get unread counts for each match
    // A message is unread if it was sent by someone else AND not present in read_receipts table
    const result = await pool.query(
      `SELECT m.id, COUNT(msg.id) as unread_count
       FROM matches m
       LEFT JOIN messages msg ON msg.match_id = m.id AND msg.sender_id != $1
       LEFT JOIN read_receipts rr ON rr.message_id = msg.id AND rr.user_id = $1
       WHERE (m.user_id_1 = $1 OR m.user_id_2 = $1)
         AND msg.id IS NOT NULL
         AND rr.id IS NULL
       GROUP BY m.id`,
      [requestedUserId]
    );

    const unreadCounts: { [key: string]: number } = {};
    result.rows.forEach(row => {
      unreadCounts[row.id] = parseInt(row.unread_count) || 0;
    });

    res.json({ success: true, unreadCounts });
  } catch (error) {
    logger.error('Failed to get unread counts', { error, requestedUserId: req.params.userId });
    res.status(500).json({ success: false, error: 'Failed to get unread counts' });
  }
});

// Mark messages as read - HTTP endpoint (WebSocket is primary, but this provides HTTP fallback)
app.put('/messages/:matchId/mark-read', authMiddleware, generalLimiter, async (req: Request, res: Response) => {
  try {
    const { matchId } = req.params;
    const authenticatedUserId = req.user!.userId;
    const { userId, messageIds } = req.body;

    if (!userId) {
      return res.status(400).json({ success: false, error: 'userId is required' });
    }

    // Authorization check: userId must match authenticated user
    if (userId !== authenticatedUserId) {
      return res.status(403).json({
        success: false,
        error: 'Forbidden: Cannot mark messages as read for another user'
      });
    }

    // Verify the user is part of this match
    const matchCheck = await pool.query(
      `SELECT user_id_1, user_id_2 FROM matches
       WHERE id = $1 AND (user_id_1 = $2 OR user_id_2 = $2)`,
      [matchId, authenticatedUserId]
    );

    if (matchCheck.rows.length === 0) {
      return res.status(403).json({
        success: false,
        error: 'Forbidden: You are not part of this match'
      });
    }

    const now = new Date();
    let query: string;
    let params: any[];

    if (messageIds && Array.isArray(messageIds) && messageIds.length > 0) {
      // Mark specific messages as read
      query = `
        UPDATE messages
        SET status = 'read', read_at = $1
        WHERE match_id = $2
          AND id = ANY($3)
          AND sender_id != $4
          AND (status != 'read' OR read_at IS NULL)
        RETURNING id
      `;
      params = [now, matchId, messageIds, authenticatedUserId];
    } else {
      // Mark all unread messages in the match as read
      query = `
        UPDATE messages
        SET status = 'read', read_at = $1
        WHERE match_id = $2
          AND sender_id != $3
          AND (status != 'read' OR read_at IS NULL)
        RETURNING id
      `;
      params = [now, matchId, authenticatedUserId];
    }

    const result = await pool.query(query, params);
    const readMessageIds = result.rows.map(row => row.id);

    // Insert read receipts
    if (readMessageIds.length > 0) {
      const receiptValues = readMessageIds.map((msgId, idx) =>
        `($${idx * 3 + 1}, $${idx * 3 + 2}, $${idx * 3 + 3})`
      ).join(', ');

      const receiptParams = readMessageIds.flatMap(msgId => [msgId, authenticatedUserId, now]);

      await pool.query(
        `INSERT INTO read_receipts (message_id, user_id, read_at)
         VALUES ${receiptValues}
         ON CONFLICT (message_id, user_id) DO NOTHING`,
        receiptParams
      );
    }

    res.json({
      success: true,
      count: readMessageIds.length,
      messageIds: readMessageIds
    });
  } catch (error) {
    logger.error('Failed to mark messages as read', { error, matchId: req.params.matchId });
    res.status(500).json({ success: false, error: 'Failed to mark messages as read' });
  }
});

// ===== SAFETY & MODERATION ENDPOINTS =====

// Delete a match (unmatch) - Only allow users to delete their own matches
app.delete('/matches/:matchId', authMiddleware, generalLimiter, async (req: Request, res: Response) => {
  try {
    const { matchId } = req.params;
    const authenticatedUserId = req.user!.userId;

    // Verify the user is part of this match before allowing deletion
    const matchCheck = await pool.query(
      `SELECT id FROM matches
       WHERE id = $1 AND (user_id_1 = $2 OR user_id_2 = $2)`,
      [matchId, authenticatedUserId]
    );

    if (matchCheck.rows.length === 0) {
      return res.status(403).json({
        success: false,
        error: 'Forbidden: You are not part of this match or match not found'
      });
    }

    const result = await pool.query(
      `DELETE FROM matches WHERE id = $1 RETURNING id`,
      [matchId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Match not found' });
    }

    // Also delete associated messages
    await pool.query(
      `DELETE FROM messages WHERE match_id = $1`,
      [matchId]
    );

    res.json({ success: true, message: 'Match deleted successfully' });
  } catch (error) {
    logger.error('Failed to delete match', { error, matchId: req.params.matchId });
    res.status(500).json({ success: false, error: 'Failed to delete match' });
  }
});

// Block a user - Verify userId matches authenticated user
app.post('/blocks', authMiddleware, generalLimiter, validateBlock, async (req: Request, res: Response) => {
  try {
    const authenticatedUserId = req.user!.userId;
    const { userId, blockedUserId, reason } = req.body;

    // Authorization check: userId must match authenticated user
    if (userId !== authenticatedUserId) {
      return res.status(403).json({
        success: false,
        error: 'Forbidden: Can only block users as yourself'
      });
    }

    if (!userId || !blockedUserId) {
      return res.status(400).json({ success: false, error: 'userId and blockedUserId are required' });
    }

    if (userId === blockedUserId) {
      return res.status(400).json({ success: false, error: 'Cannot block yourself' });
    }

    // Check if already blocked
    const existing = await pool.query(
      `SELECT id FROM blocks WHERE user_id = $1 AND blocked_user_id = $2`,
      [userId, blockedUserId]
    );

    if (existing.rows.length > 0) {
      return res.json({ success: true, message: 'User already blocked' });
    }

    const blockId = `block_${Date.now()}`;

    await pool.query(
      `INSERT INTO blocks (id, user_id, blocked_user_id, reason)
       VALUES ($1, $2, $3, $4)`,
      [blockId, userId, blockedUserId, reason || null]
    );

    // Delete any existing matches
    await pool.query(
      `DELETE FROM matches
       WHERE (user_id_1 = $1 AND user_id_2 = $2)
          OR (user_id_1 = $2 AND user_id_2 = $1)`,
      [userId, blockedUserId]
    );

    res.json({ success: true, message: 'User blocked successfully' });
  } catch (error) {
    logger.error('Failed to block user', { error, userId: req.body.userId, blockedUserId: req.body.blockedUserId });
    res.status(500).json({ success: false, error: 'Failed to block user' });
  }
});

// Unblock a user - Only allow users to unblock for themselves
app.delete('/blocks/:userId/:blockedUserId', authMiddleware, generalLimiter, async (req: Request, res: Response) => {
  try {
    const { userId, blockedUserId } = req.params;
    const authenticatedUserId = req.user!.userId;

    // Authorization check: userId must match authenticated user
    if (userId !== authenticatedUserId) {
      return res.status(403).json({
        success: false,
        error: 'Forbidden: Can only unblock users for yourself'
      });
    }

    const result = await pool.query(
      `DELETE FROM blocks WHERE user_id = $1 AND blocked_user_id = $2 RETURNING id`,
      [userId, blockedUserId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Block not found' });
    }

    res.json({ success: true, message: 'User unblocked successfully' });
  } catch (error) {
    logger.error('Failed to unblock user', { error, userId: req.params.userId, blockedUserId: req.params.blockedUserId });
    res.status(500).json({ success: false, error: 'Failed to unblock user' });
  }
});

// Get blocked users for a user - Only allow users to view their own blocks
app.get('/blocks/:userId', authMiddleware, generalLimiter, async (req: Request, res: Response) => {
  try {
    const { userId } = req.params;
    const authenticatedUserId = req.user!.userId;

    // Authorization check: user can only view their own blocked users
    if (userId !== authenticatedUserId) {
      return res.status(403).json({
        success: false,
        error: 'Forbidden: Cannot access other users\' blocked list'
      });
    }

    const result = await pool.query(
      `SELECT id, user_id, blocked_user_id, reason, created_at
       FROM blocks
       WHERE user_id = $1
       ORDER BY created_at DESC`,
      [userId]
    );

    const blockedUsers = result.rows.map(block => ({
      id: block.id,
      userId: block.user_id,
      blockedUserId: block.blocked_user_id,
      reason: block.reason,
      createdAt: block.created_at
    }));

    res.json({ success: true, blockedUsers });
  } catch (error) {
    logger.error('Failed to retrieve blocked users', { error, userId: req.params.userId });
    res.status(500).json({ success: false, error: 'Failed to retrieve blocked users' });
  }
});

// Report a user - Verify reporterId matches authenticated user
app.post('/reports', authMiddleware, reportLimiter, validateReport, async (req: Request, res: Response) => {
  try {
    const authenticatedUserId = req.user!.userId;
    const { reporterId, reportedUserId, reason, details } = req.body;

    // Authorization check: reporterId must match authenticated user
    if (reporterId !== authenticatedUserId) {
      return res.status(403).json({
        success: false,
        error: 'Forbidden: Can only submit reports as yourself'
      });
    }

    if (!reporterId || !reportedUserId || !reason) {
      return res.status(400).json({
        success: false,
        error: 'reporterId, reportedUserId, and reason are required'
      });
    }

    if (reporterId === reportedUserId) {
      return res.status(400).json({ success: false, error: 'Cannot report yourself' });
    }

    const reportId = `report_${Date.now()}`;

    await pool.query(
      `INSERT INTO reports (id, reporter_id, reported_user_id, reason, details, status)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [reportId, reporterId, reportedUserId, reason, details || null, 'pending']
    );

    res.json({
      success: true,
      message: 'Report submitted successfully. Our moderation team will review it.'
    });
  } catch (error) {
    logger.error('Failed to submit report', { error, reporterId: req.body.reporterId, reportedUserId: req.body.reportedUserId });
    res.status(500).json({ success: false, error: 'Failed to submit report' });
  }
});

// Get reports (for moderation - requires admin API key)
app.get('/reports', generalLimiter, requireAdminAuth, async (req: Request, res: Response) => {
  try {
    const { status } = req.query;

    let query = `SELECT id, reporter_id, reported_user_id, reason, details, status, created_at
                 FROM reports`;
    const params: any[] = [];

    if (status) {
      query += ' WHERE status = $1';
      params.push(status);
    }

    query += ' ORDER BY created_at DESC LIMIT 100';

    const result = await pool.query(query, params);

    const reports = result.rows.map(report => ({
      id: report.id,
      reporterId: report.reporter_id,
      reportedUserId: report.reported_user_id,
      reason: report.reason,
      details: report.details,
      status: report.status,
      createdAt: report.created_at
    }));

    res.json({ success: true, reports });
  } catch (error) {
    logger.error('Failed to retrieve reports', { error });
    res.status(500).json({ success: false, error: 'Failed to retrieve reports' });
  }
});

// Register FCM token for push notifications
app.post('/fcm/register', authMiddleware, generalLimiter, async (req: Request, res: Response) => {
  try {
    const authenticatedUserId = req.user!.userId;
    const { token, deviceType, deviceId } = req.body;

    if (!token || !deviceType) {
      return res.status(400).json({
        success: false,
        error: 'token and deviceType are required'
      });
    }

    if (!['ios', 'android', 'web'].includes(deviceType)) {
      return res.status(400).json({
        success: false,
        error: 'deviceType must be ios, android, or web'
      });
    }

    await registerFCMToken(pool, authenticatedUserId, token, deviceType, deviceId);

    res.json({
      success: true,
      message: 'FCM token registered successfully'
    });
  } catch (error) {
    logger.error('Failed to register FCM token', { error, userId: req.user?.userId });
    res.status(500).json({ success: false, error: 'Failed to register FCM token' });
  }
});

// Unregister FCM token
app.post('/fcm/unregister', authMiddleware, generalLimiter, async (req: Request, res: Response) => {
  try {
    const authenticatedUserId = req.user!.userId;
    const { token } = req.body;

    if (!token) {
      return res.status(400).json({
        success: false,
        error: 'token is required'
      });
    }

    await unregisterFCMToken(pool, authenticatedUserId, token);

    res.json({
      success: true,
      message: 'FCM token unregistered successfully'
    });
  } catch (error) {
    logger.error('Failed to unregister FCM token', { error, userId: req.user?.userId });
    res.status(500).json({ success: false, error: 'Failed to unregister FCM token' });
  }
});

// ===== DATE PROPOSAL ENDPOINTS =====

// Helper function to award date completion tickets
async function awardDateCompletionTicket(userId: string, dateId: string): Promise<void> {
  try {
    await pool.query(
      `INSERT INTO ticket_ledger (user_id, amount, reason, reference_id) VALUES ($1, 1, 'date_completed', $2)`,
      [userId, dateId]
    );
    logger.info('Awarded date completion ticket', { userId, dateId });
  } catch (error) {
    logger.error('Failed to award date completion ticket', { error, userId, dateId });
  }
}

// Helper function to award referral bonus when referred user completes a date
async function awardReferralBonus(userId: string, dateId: string): Promise<void> {
  try {
    // Check if user was referred by someone
    const referrerResult = await pool.query(
      `SELECT referred_by FROM users WHERE id = $1`,
      [userId]
    );
    const referrerId = referrerResult.rows[0]?.referred_by;

    if (referrerId) {
      await pool.query(
        `INSERT INTO ticket_ledger (user_id, amount, reason, reference_id) VALUES ($1, 1, 'referral_bonus', $2)`,
        [referrerId, dateId]
      );
      logger.info('Awarded referral bonus ticket', { referrerId, referredUserId: userId, dateId });
    }
  } catch (error) {
    logger.error('Failed to award referral bonus', { error, userId, dateId });
  }
}

// Create a date proposal
app.post('/dates', authMiddleware, generalLimiter, async (req: Request, res: Response) => {
  try {
    const authenticatedUserId = req.user!.userId;
    const {
      matchId,
      placeId,
      placeName,
      placeAddress,
      placeLat,
      placeLng,
      proposedDate,
      proposedTime,
      note
    } = req.body;

    // Validate required fields
    if (!matchId || !placeName || !proposedDate || !proposedTime) {
      return res.status(400).json({
        success: false,
        error: 'matchId, placeName, proposedDate, and proposedTime are required'
      });
    }

    // Verify user is part of this match
    const matchResult = await pool.query(
      `SELECT user_id_1, user_id_2 FROM matches WHERE id = $1`,
      [matchId]
    );

    if (matchResult.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Match not found' });
    }

    const match = matchResult.rows[0];
    if (match.user_id_1 !== authenticatedUserId && match.user_id_2 !== authenticatedUserId) {
      return res.status(403).json({ success: false, error: 'Not authorized for this match' });
    }

    // Check if there's already a pending proposal for this match
    const existingProposal = await pool.query(
      `SELECT id FROM date_proposals WHERE match_id = $1 AND status = 'pending'`,
      [matchId]
    );

    if (existingProposal.rows.length > 0) {
      return res.status(400).json({
        success: false,
        error: 'There is already a pending date proposal for this match'
      });
    }

    // Create the proposal
    const result = await pool.query(
      `INSERT INTO date_proposals (
        match_id, proposer_id, place_id, place_name, place_address,
        place_lat, place_lng, proposed_date, proposed_time, note
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
      RETURNING *`,
      [
        matchId,
        authenticatedUserId,
        placeId || null,
        placeName,
        placeAddress || null,
        placeLat || null,
        placeLng || null,
        proposedDate,
        proposedTime,
        note || null
      ]
    );

    const proposal = result.rows[0];

    logger.info('Date proposal created', {
      proposalId: proposal.id,
      matchId,
      proposerId: authenticatedUserId,
      placeName,
      proposedDate
    });

    res.json({
      success: true,
      proposal: {
        id: proposal.id,
        matchId: proposal.match_id,
        proposerId: proposal.proposer_id,
        placeId: proposal.place_id,
        placeName: proposal.place_name,
        placeAddress: proposal.place_address,
        placeLat: proposal.place_lat,
        placeLng: proposal.place_lng,
        proposedDate: proposal.proposed_date,
        proposedTime: proposal.proposed_time,
        note: proposal.note,
        status: proposal.status,
        createdAt: proposal.created_at
      }
    });
  } catch (error) {
    logger.error('Failed to create date proposal', { error, userId: req.user?.userId });
    res.status(500).json({ success: false, error: 'Failed to create date proposal' });
  }
});

// Get date proposals for a match
app.get('/dates/:matchId', authMiddleware, generalLimiter, async (req: Request, res: Response) => {
  try {
    const authenticatedUserId = req.user!.userId;
    const { matchId } = req.params;

    // Verify user is part of this match
    const matchResult = await pool.query(
      `SELECT user_id_1, user_id_2 FROM matches WHERE id = $1`,
      [matchId]
    );

    if (matchResult.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Match not found' });
    }

    const match = matchResult.rows[0];
    if (match.user_id_1 !== authenticatedUserId && match.user_id_2 !== authenticatedUserId) {
      return res.status(403).json({ success: false, error: 'Not authorized for this match' });
    }

    const result = await pool.query(
      `SELECT dp.*, p.name as proposer_name
       FROM date_proposals dp
       JOIN profiles p ON dp.proposer_id = p.user_id
       WHERE dp.match_id = $1
       ORDER BY dp.created_at DESC`,
      [matchId]
    );

    const proposals = result.rows.map(row => ({
      id: row.id,
      matchId: row.match_id,
      proposerId: row.proposer_id,
      proposerName: row.proposer_name,
      placeId: row.place_id,
      placeName: row.place_name,
      placeAddress: row.place_address,
      placeLat: row.place_lat,
      placeLng: row.place_lng,
      proposedDate: row.proposed_date,
      proposedTime: row.proposed_time,
      note: row.note,
      status: row.status,
      respondedAt: row.responded_at,
      completedAt: row.completed_at,
      proposerConfirmed: row.proposer_confirmed,
      recipientConfirmed: row.recipient_confirmed,
      createdAt: row.created_at
    }));

    res.json({ success: true, proposals });
  } catch (error) {
    logger.error('Failed to get date proposals', { error, userId: req.user?.userId });
    res.status(500).json({ success: false, error: 'Failed to get date proposals' });
  }
});

// Respond to a date proposal (accept/decline)
app.put('/dates/:id/respond', authMiddleware, generalLimiter, async (req: Request, res: Response) => {
  try {
    const authenticatedUserId = req.user!.userId;
    const { id } = req.params;
    const { response, counterDate, counterTime } = req.body;

    if (!response || !['accepted', 'declined'].includes(response)) {
      return res.status(400).json({
        success: false,
        error: 'response must be "accepted" or "declined"'
      });
    }

    // Get the proposal and verify the user is the recipient
    const proposalResult = await pool.query(
      `SELECT dp.*, m.user_id_1, m.user_id_2
       FROM date_proposals dp
       JOIN matches m ON dp.match_id = m.id
       WHERE dp.id = $1`,
      [id]
    );

    if (proposalResult.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Date proposal not found' });
    }

    const proposal = proposalResult.rows[0];

    // Verify user is part of the match but not the proposer
    const isInMatch = proposal.user_id_1 === authenticatedUserId || proposal.user_id_2 === authenticatedUserId;
    if (!isInMatch) {
      return res.status(403).json({ success: false, error: 'Not authorized for this proposal' });
    }

    if (proposal.proposer_id === authenticatedUserId) {
      return res.status(400).json({ success: false, error: 'Cannot respond to your own proposal' });
    }

    if (proposal.status !== 'pending') {
      return res.status(400).json({ success: false, error: 'Proposal has already been responded to' });
    }

    // Update the proposal
    await pool.query(
      `UPDATE date_proposals SET status = $1, responded_at = NOW(), updated_at = NOW() WHERE id = $2`,
      [response, id]
    );

    logger.info('Date proposal response', {
      proposalId: id,
      responderId: authenticatedUserId,
      response
    });

    // If counter-proposal provided and declined, create new proposal
    if (response === 'declined' && counterDate && counterTime) {
      const counterResult = await pool.query(
        `INSERT INTO date_proposals (
          match_id, proposer_id, place_id, place_name, place_address,
          place_lat, place_lng, proposed_date, proposed_time, note
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
        RETURNING id`,
        [
          proposal.match_id,
          authenticatedUserId,
          proposal.place_id,
          proposal.place_name,
          proposal.place_address,
          proposal.place_lat,
          proposal.place_lng,
          counterDate,
          counterTime,
          'Counter-proposal: How about this time instead?'
        ]
      );

      logger.info('Counter-proposal created', {
        originalProposalId: id,
        counterProposalId: counterResult.rows[0].id
      });

      return res.json({
        success: true,
        message: 'Proposal declined with counter-offer',
        counterProposalId: counterResult.rows[0].id
      });
    }

    res.json({
      success: true,
      message: response === 'accepted' ? 'Date accepted!' : 'Date declined',
      status: response
    });
  } catch (error) {
    logger.error('Failed to respond to date proposal', { error, userId: req.user?.userId });
    res.status(500).json({ success: false, error: 'Failed to respond to date proposal' });
  }
});

// Confirm a date happened (both users must confirm)
app.put('/dates/:id/confirm', authMiddleware, generalLimiter, async (req: Request, res: Response) => {
  try {
    const authenticatedUserId = req.user!.userId;
    const { id } = req.params;

    // Get the proposal
    const proposalResult = await pool.query(
      `SELECT dp.*, m.user_id_1, m.user_id_2
       FROM date_proposals dp
       JOIN matches m ON dp.match_id = m.id
       WHERE dp.id = $1`,
      [id]
    );

    if (proposalResult.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Date proposal not found' });
    }

    const proposal = proposalResult.rows[0];

    // Verify user is part of the match
    const isInMatch = proposal.user_id_1 === authenticatedUserId || proposal.user_id_2 === authenticatedUserId;
    if (!isInMatch) {
      return res.status(403).json({ success: false, error: 'Not authorized for this proposal' });
    }

    if (proposal.status !== 'accepted') {
      return res.status(400).json({ success: false, error: 'Can only confirm accepted dates' });
    }

    // Determine if user is proposer or recipient
    const isProposer = proposal.proposer_id === authenticatedUserId;
    const updateColumn = isProposer ? 'proposer_confirmed' : 'recipient_confirmed';

    // Check if already confirmed
    if ((isProposer && proposal.proposer_confirmed) || (!isProposer && proposal.recipient_confirmed)) {
      return res.status(400).json({ success: false, error: 'You have already confirmed this date' });
    }

    // Update confirmation
    await pool.query(
      `UPDATE date_proposals SET ${updateColumn} = TRUE, updated_at = NOW() WHERE id = $1`,
      [id]
    );

    // Check if both have confirmed
    const otherConfirmed = isProposer ? proposal.recipient_confirmed : proposal.proposer_confirmed;

    if (otherConfirmed) {
      // Both confirmed - mark as completed and award tickets
      await pool.query(
        `UPDATE date_proposals SET status = 'completed', completed_at = NOW(), updated_at = NOW() WHERE id = $1`,
        [id]
      );

      // Award tickets to both users
      const otherUserId = proposal.user_id_1 === authenticatedUserId ? proposal.user_id_2 : proposal.user_id_1;

      await Promise.all([
        awardDateCompletionTicket(authenticatedUserId, id),
        awardDateCompletionTicket(otherUserId, id),
        awardReferralBonus(authenticatedUserId, id),
        awardReferralBonus(otherUserId, id)
      ]);

      logger.info('Date completed', {
        proposalId: id,
        user1: authenticatedUserId,
        user2: otherUserId
      });

      return res.json({
        success: true,
        message: 'Date confirmed! You both earned a Golden Ticket!',
        completed: true,
        ticketAwarded: true
      });
    }

    res.json({
      success: true,
      message: 'Your confirmation recorded. Waiting for the other person to confirm.',
      completed: false
    });
  } catch (error) {
    logger.error('Failed to confirm date', { error, userId: req.user?.userId });
    res.status(500).json({ success: false, error: 'Failed to confirm date' });
  }
});

// Cancel a date proposal
app.delete('/dates/:id', authMiddleware, generalLimiter, async (req: Request, res: Response) => {
  try {
    const authenticatedUserId = req.user!.userId;
    const { id } = req.params;

    // Get the proposal
    const proposalResult = await pool.query(
      `SELECT * FROM date_proposals WHERE id = $1`,
      [id]
    );

    if (proposalResult.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Date proposal not found' });
    }

    const proposal = proposalResult.rows[0];

    // Only the proposer can cancel
    if (proposal.proposer_id !== authenticatedUserId) {
      return res.status(403).json({ success: false, error: 'Only the proposer can cancel' });
    }

    if (['completed', 'cancelled'].includes(proposal.status)) {
      return res.status(400).json({ success: false, error: 'Cannot cancel this proposal' });
    }

    await pool.query(
      `UPDATE date_proposals SET status = 'cancelled', updated_at = NOW() WHERE id = $1`,
      [id]
    );

    logger.info('Date proposal cancelled', { proposalId: id, userId: authenticatedUserId });

    res.json({ success: true, message: 'Date proposal cancelled' });
  } catch (error) {
    logger.error('Failed to cancel date proposal', { error, userId: req.user?.userId });
    res.status(500).json({ success: false, error: 'Failed to cancel date proposal' });
  }
});

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

// Create HTTP server and initialize Socket.IO
const httpServer = createServer(app);
const io = initializeSocketIO(httpServer, pool);

// Only start server if not in test environment
if (process.env.NODE_ENV !== 'test') {
  httpServer.listen(PORT, () => {
    logger.info(`Chat service started with Socket.IO`, {
      port: PORT,
      environment: process.env.NODE_ENV || 'development'
    });
  });
}

// Export for testing
export default app;
export { io, httpServer };
