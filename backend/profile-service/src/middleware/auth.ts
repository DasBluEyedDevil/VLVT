/**
 * Profile Service Auth Middleware
 * Re-exports shared auth middleware for profile-service usage
 */

export {
  authMiddleware,
  authenticateJWT,
  createAuthMiddleware,
  type AuthMiddlewareOptions,
  type JWTPayload,
} from '@vlvt/shared';

// Default export for backwards compatibility
import { authMiddleware } from '@vlvt/shared';
export default authMiddleware;
