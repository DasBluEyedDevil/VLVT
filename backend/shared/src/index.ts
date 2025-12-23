/**
 * @vlvt/shared - Shared utilities and middleware for VLVT microservices
 *
 * This package centralizes common functionality to eliminate code duplication
 * and ensure consistent behavior across all backend services.
 */

// Types
export * from './types/express';
export * from './types/api';

// Middleware
export {
  authMiddleware,
  authenticateJWT,
  createAuthMiddleware,
  type AuthMiddlewareOptions,
  type JWTPayload,
} from './middleware/auth';

export {
  createRateLimiter,
  generalLimiter,
  strictLimiter,
  authLimiter,
  profileCreationLimiter,
  discoveryLimiter,
  messageLimiter,
  uploadLimiter,
  type RateLimiterOptions,
} from './middleware/rate-limiter';

export {
  errorHandler,
  createErrorHandler,
  notFoundHandler,
  asyncHandler,
  ApiError,
  type ErrorHandlerOptions,
} from './middleware/error-handler';

// Utilities
export {
  createLogger,
  defaultLogger,
  type LoggerOptions,
} from './utils/logger';

export {
  validateEnv,
  validators,
  serviceEnvConfigs,
  type EnvConfig,
  type ValidationResult,
} from './utils/env-validator';

export {
  sendSuccess,
  sendSuccessMessage,
  sendError,
  sendPaginated,
  errors,
} from './utils/response';

// Services
export {
  initializeFirebase,
  isFirebaseReady,
  setFCMLogger,
  sendPushNotification,
  sendMessageNotification,
  sendMatchNotification,
  sendTypingNotification,
  registerFCMToken,
  unregisterFCMToken,
  deactivateAllUserTokens,
} from './services/fcm-service';
