/**
 * Socket.IO Authentication Middleware
 * Validates JWT tokens for WebSocket connections
 */

import { Socket } from 'socket.io';
import jwt from 'jsonwebtoken';
import logger from '../utils/logger';

interface AuthToken {
  userId: string;
  provider: string;
  iat?: number;
  exp?: number;
}

interface SocketWithAuth extends Socket {
  userId?: string;
  provider?: string;
}

/**
 * Socket.IO authentication middleware
 * Verifies JWT token from handshake auth
 */
export const socketAuthMiddleware = (socket: SocketWithAuth, next: (err?: Error) => void) => {
  try {
    // Get token from handshake auth
    const token = socket.handshake.auth.token;

    if (!token) {
      logger.warn('Socket connection attempt without token', {
        socketId: socket.id,
        address: socket.handshake.address
      });
      return next(new Error('Authentication token required'));
    }

    // Verify JWT token
    const jwtSecret = process.env.JWT_SECRET;
    if (!jwtSecret) {
      logger.error('JWT_SECRET not configured');
      return next(new Error('Server configuration error'));
    }

    // Explicitly specify allowed algorithms to prevent algorithm confusion attacks
    const decoded = jwt.verify(token, jwtSecret, { algorithms: ['HS256'] }) as AuthToken;

    // Attach user info to socket
    socket.userId = decoded.userId;
    socket.provider = decoded.provider;

    logger.info('Socket authenticated successfully', {
      socketId: socket.id,
      userId: decoded.userId,
      provider: decoded.provider
    });

    next();
  } catch (error) {
    if (error instanceof jwt.JsonWebTokenError) {
      logger.warn('Invalid JWT token for socket connection', {
        socketId: socket.id,
        error: error.message
      });
      return next(new Error('Invalid authentication token'));
    }

    if (error instanceof jwt.TokenExpiredError) {
      logger.warn('Expired JWT token for socket connection', {
        socketId: socket.id
      });
      return next(new Error('Token expired'));
    }

    logger.error('Socket authentication error', {
      socketId: socket.id,
      error: error instanceof Error ? error.message : 'Unknown error'
    });
    return next(new Error('Authentication failed'));
  }
};

export type { SocketWithAuth };
