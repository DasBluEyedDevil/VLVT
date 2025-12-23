/**
 * Chat Service Auth Middleware
 * Re-exports shared auth middleware for chat-service usage
 */

export {
  authMiddleware,
  authenticateJWT,
  createAuthMiddleware,
  type AuthMiddlewareOptions,
  type JWTPayload,
} from '../shared';

// Default export for backwards compatibility
import { authMiddleware } from '../shared';
export default authMiddleware;
