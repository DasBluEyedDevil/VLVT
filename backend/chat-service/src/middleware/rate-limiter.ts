/**
 * Chat Service Rate Limiter
 * Re-exports shared rate limiters + service-specific limiters
 */

import { createRateLimiter } from '../shared';

// Re-export shared limiters
export {
  createRateLimiter,
  generalLimiter,
  strictLimiter,
  authLimiter,
  messageLimiter,
  type RateLimiterOptions,
} from '../shared';

// Chat-service specific limiters
export const verifyLimiter = createRateLimiter({
  windowMs: 15 * 60 * 1000,
  max: 100,
  message: 'Too many verification requests, please try again later',
});

export const matchLimiter = createRateLimiter({
  windowMs: 15 * 60 * 1000,
  max: 15,
  message: 'Too many match attempts, please try again later',
});

export const reportLimiter = createRateLimiter({
  windowMs: 24 * 60 * 60 * 1000,
  max: 10,
  message: 'Too many reports submitted, please try again tomorrow',
});
