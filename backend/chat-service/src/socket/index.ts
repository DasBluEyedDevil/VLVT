/**
 * Socket.IO Server Setup
 * Configures and initializes Socket.IO for real-time messaging
 */

import { Server as HttpServer } from 'http';
import { Server as SocketServer } from 'socket.io';
import { Pool } from 'pg';
import logger from '../utils/logger';
import { socketAuthMiddleware, SocketWithAuth } from './auth-middleware';
import { setupMessageHandlers, updateUserStatus } from './message-handler';

/**
 * Initialize and configure Socket.IO server
 */
export const initializeSocketIO = (httpServer: HttpServer, pool: Pool): SocketServer => {
  const corsOrigin = process.env.CORS_ORIGIN || 'http://localhost:19006';

  // Create Socket.IO server with configuration
  const io = new SocketServer(httpServer, {
    cors: {
      origin: corsOrigin,
      methods: ['GET', 'POST'],
      credentials: true
    },
    pingTimeout: 60000, // 60 seconds
    pingInterval: 25000, // 25 seconds
    transports: ['websocket', 'polling'], // Support both for better compatibility
    allowEIO3: true // Support older Socket.IO clients
  });

  logger.info('Socket.IO server initialized', { corsOrigin });

  // Apply authentication middleware
  io.use(socketAuthMiddleware);

  // Handle new connections
  io.on('connection', async (socket: SocketWithAuth) => {
    const userId = socket.userId!;

    logger.info('Client connected', {
      socketId: socket.id,
      userId,
      transport: socket.conn.transport.name
    });

    // Join user-specific room for direct messaging
    socket.join(`user:${userId}`);

    // Update user status to online
    await updateUserStatus(pool, userId, true, socket.id);

    // Broadcast online status to user's matches
    await broadcastOnlineStatus(io, pool, userId, true);

    // Setup message event handlers
    setupMessageHandlers(io, socket, pool);

    // Handle disconnection
    socket.on('disconnect', async (reason) => {
      logger.info('Client disconnected', {
        socketId: socket.id,
        userId,
        reason
      });

      // Update user status to offline
      await updateUserStatus(pool, userId, false, undefined);

      // Broadcast offline status to user's matches
      await broadcastOnlineStatus(io, pool, userId, false);
    });

    // Handle errors
    socket.on('error', (error) => {
      logger.error('Socket error', {
        socketId: socket.id,
        userId,
        error: error.message
      });
    });

    // Ping/pong for connection health monitoring
    socket.on('ping', (callback) => {
      callback?.({ timestamp: Date.now() });
    });
  });

  // Handle server-level errors
  io.engine.on('connection_error', (err) => {
    logger.error('Socket.IO connection error', {
      code: err.code,
      message: err.message,
      context: err.context
    });
  });

  return io;
};

/**
 * Broadcast user's online status to their matches
 */
async function broadcastOnlineStatus(
  io: SocketServer,
  pool: Pool,
  userId: string,
  isOnline: boolean
) {
  try {
    // Get all matches for this user
    const result = await pool.query(
      `SELECT
        CASE
          WHEN user_id_1 = $1 THEN user_id_2
          ELSE user_id_1
        END as match_user_id
       FROM matches
       WHERE user_id_1 = $1 OR user_id_2 = $1`,
      [userId]
    );

    const matchUserIds = result.rows.map(row => row.match_user_id);

    // Emit status update to each match
    matchUserIds.forEach(matchUserId => {
      io.to(`user:${matchUserId}`).emit('user_status_changed', {
        userId,
        isOnline,
        timestamp: new Date()
      });
    });

    logger.debug('Broadcasted online status', {
      userId,
      isOnline,
      recipientCount: matchUserIds.length
    });
  } catch (error) {
    logger.error('Error broadcasting online status', {
      error: error instanceof Error ? error.message : 'Unknown error',
      userId,
      isOnline
    });
  }
}

/**
 * Send push notification for new message (if user is offline)
 * Note: This function is deprecated and kept for backward compatibility.
 * The actual FCM notification is now sent directly from message-handler.ts
 * using the fcm-service module.
 */
export async function sendMessageNotification(
  pool: Pool,
  recipientId: string,
  senderId: string,
  matchId: string,
  messageText: string
) {
  logger.warn('Deprecated sendMessageNotification called - use fcm-service directly', {
    recipientId,
    senderId,
    matchId
  });
  // This function is kept for compatibility but doesn't do anything
  // FCM notifications are now handled in message-handler.ts
}

export type { SocketServer };
