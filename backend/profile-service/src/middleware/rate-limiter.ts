/**
 * Profile Service Rate Limiter
 * Re-exports shared rate limiters + service-specific limiters
 */

import { createRateLimiter } from '../shared';

// Re-export shared limiters
export {
  createRateLimiter,
  generalLimiter,
  strictLimiter,
  authLimiter,
  profileCreationLimiter,
  discoveryLimiter,
  uploadLimiter,
  type RateLimiterOptions,
} from '../shared';

// Profile-service specific limiters
export const verifyLimiter = createRateLimiter({
  windowMs: 15 * 60 * 1000,
  max: 100,
  message: 'Too many verification requests, please try again later',
});
