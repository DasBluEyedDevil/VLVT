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

import express, { Request, Response } from 'express';
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

const app = express();
const PORT = process.env.PORT || 3003;

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

// Security middleware
app.use(helmet());
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
      'SELECT id, name FROM profiles WHERE id IN ($1, $2)',
      [userId1, userId2]
    );

    if (profilesResult.rows.length === 2) {
      const user1Profile = profilesResult.rows.find((p: any) => p.id === userId1);
      const user2Profile = profilesResult.rows.find((p: any) => p.id === userId2);

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
  } catch (error) {
    logger.error('Failed to create match', { error, authenticatedUserId: req.user?.userId });
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
    // A message is unread if it was sent by someone else and created after the user last viewed the chat
    // For MVP, we'll count all messages not sent by the user as potentially unread
    const result = await pool.query(
      `SELECT m.match_id, COUNT(msg.id) as unread_count
       FROM matches m
       LEFT JOIN messages msg ON msg.match_id = m.id AND msg.sender_id != $1
       WHERE m.user_id_1 = $1 OR m.user_id_2 = $1
       GROUP BY m.match_id`,
      [requestedUserId]
    );

    const unreadCounts: { [key: string]: number } = {};
    result.rows.forEach(row => {
      unreadCounts[row.match_id] = parseInt(row.unread_count) || 0;
    });

    res.json({ success: true, unreadCounts });
  } catch (error) {
    logger.error('Failed to get unread counts', { error, requestedUserId: req.params.userId });
    res.status(500).json({ success: false, error: 'Failed to get unread counts' });
  }
});

// Mark messages as read (placeholder for future implementation)
// This would require adding a read_at timestamp to messages or a separate read_receipts table
app.put('/messages/:matchId/mark-read', authMiddleware, generalLimiter, async (req: Request, res: Response) => {
  try {
    const { matchId } = req.params;
    const authenticatedUserId = req.user!.userId;
    const { userId } = req.body;

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

    // For now, just return success
    // In a full implementation, this would update a read_receipts table or add timestamps
    res.json({ success: true, message: 'Messages marked as read (placeholder)' });
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

// Get reports (for moderation - would need admin auth in production)
app.get('/reports', generalLimiter, async (req: Request, res: Response) => {
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
