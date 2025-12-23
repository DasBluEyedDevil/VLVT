/**
 * Shared JWT Authentication Middleware
 * Centralizes auth logic for all VLVT microservices
 */

import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import type { JWTPayload } from '../types/express';

// Re-export type for convenience
export type { JWTPayload };

export interface AuthMiddlewareOptions {
  /** Custom JWT secret (defaults to JWT_SECRET env var) */
  jwtSecret?: string;
  /** Allowed algorithms (defaults to HS256 only for security) */
  algorithms?: jwt.Algorithm[];
  /** Skip auth for specific paths */
  skipPaths?: string[];
  /** Custom logger function */
  logger?: {
    error: (message: string, meta?: object) => void;
  };
}

/**
 * Create a configured auth middleware instance
 */
export const createAuthMiddleware = (options: AuthMiddlewareOptions = {}) => {
  const {
    algorithms = ['HS256'],
    skipPaths = [],
    logger = console,
  } = options;

  return (req: Request, res: Response, next: NextFunction): void => {
    // Skip authentication for specified paths
    if (skipPaths.some(path => req.path.startsWith(path))) {
      return next();
    }

    const jwtSecret = options.jwtSecret || process.env.JWT_SECRET;
    if (!jwtSecret) {
      logger.error('JWT_SECRET not configured');
      res.status(500).json({ success: false, error: 'Server configuration error' });
      return;
    }

    const authHeader = req.headers.authorization;
    if (!authHeader) {
      res.status(401).json({ success: false, error: 'No authorization header provided' });
      return;
    }

    if (!authHeader.startsWith('Bearer ')) {
      res.status(401).json({ success: false, error: 'Invalid authorization header format. Use: Bearer <token>' });
      return;
    }

    const token = authHeader.substring(7);
    if (!token) {
      res.status(401).json({ success: false, error: 'No token provided' });
      return;
    }

    try {
      // Explicitly specify allowed algorithms to prevent algorithm confusion attacks
      const decoded = jwt.verify(token, jwtSecret, { algorithms }) as JWTPayload;

      req.user = {
        userId: decoded.userId,
        provider: decoded.provider,
        email: decoded.email,
      };

      next();
    } catch (error) {
      if (error instanceof jwt.TokenExpiredError) {
        res.status(401).json({ success: false, error: 'Token expired' });
        return;
      }
      if (error instanceof jwt.JsonWebTokenError) {
        res.status(401).json({ success: false, error: 'Invalid token' });
        return;
      }
      logger.error('Authentication error', { error });
      res.status(500).json({ success: false, error: 'Authentication failed' });
    }
  };
};

/**
 * Default auth middleware with standard configuration
 * Uses JWT_SECRET from environment and HS256 algorithm
 */
export const authMiddleware = createAuthMiddleware();

/**
 * Alias for backward compatibility
 */
export const authenticateJWT = authMiddleware;
