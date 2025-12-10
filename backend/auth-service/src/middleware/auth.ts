import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import logger from '../utils/logger';

// Extend Express Request type to include user property
declare global {
  namespace Express {
    interface Request {
      user?: {
        userId: string;
        provider: string;
        email: string;
      };
    }
  }
}

// JWT authentication middleware
export const authenticateJWT = (req: Request, res: Response, next: NextFunction): void => {
  try {
    // Extract token from Authorization header
    const authHeader = req.headers.authorization;

    if (!authHeader) {
      res.status(401).json({ success: false, error: 'No authorization header provided' });
      return;
    }

    // Check if the header starts with 'Bearer '
    if (!authHeader.startsWith('Bearer ')) {
      res.status(401).json({ success: false, error: 'Invalid authorization header format. Use: Bearer <token>' });
      return;
    }

    // Extract the token
    const token = authHeader.substring(7); // Remove 'Bearer ' prefix

    if (!token) {
      res.status(401).json({ success: false, error: 'No token provided' });
      return;
    }

    // Verify the JWT token
    const JWT_SECRET = process.env.JWT_SECRET;
    if (!JWT_SECRET) {
      logger.error('JWT_SECRET environment variable is not set');
      res.status(500).json({ success: false, error: 'Server configuration error' });
      return;
    }

    // Explicitly specify allowed algorithms to prevent algorithm confusion attacks
    const decoded = jwt.verify(token, JWT_SECRET, { algorithms: ['HS256'] }) as {
      userId: string;
      provider: string;
      email: string;
    };

    // Attach user info to request object
    req.user = {
      userId: decoded.userId,
      provider: decoded.provider,
      email: decoded.email
    };

    // Continue to next middleware or route handler
    next();
  } catch (error) {
    if (error instanceof jwt.JsonWebTokenError) {
      res.status(401).json({ success: false, error: 'Invalid token' });
      return;
    }
    if (error instanceof jwt.TokenExpiredError) {
      res.status(401).json({ success: false, error: 'Token expired' });
      return;
    }
    logger.error('Authentication error', { error });
    res.status(500).json({ success: false, error: 'Authentication failed' });
  }
};
