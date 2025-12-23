/**
 * Shared Rate Limiting Middleware
 * Centralizes rate limiting configuration for all VLVT microservices
 */

import rateLimit, { RateLimitRequestHandler, Options } from 'express-rate-limit';

export interface RateLimiterOptions {
  /** Window duration in milliseconds */
  windowMs?: number;
  /** Max requests per window */
  max?: number;
  /** Error message when limit exceeded */
  message?: string;
  /** Skip rate limiting for certain requests */
  skip?: Options['skip'];
  /** Custom key generator */
  keyGenerator?: Options['keyGenerator'];
}

/**
 * Create a rate limiter with custom options
 */
export const createRateLimiter = (options: RateLimiterOptions = {}): RateLimitRequestHandler => {
  const {
    windowMs = 15 * 60 * 1000, // 15 minutes default
    max = 100, // 100 requests per window default
    message = 'Too many requests, please try again later.',
    skip,
    keyGenerator,
  } = options;

  return rateLimit({
    windowMs,
    max,
    message: { success: false, error: message },
    standardHeaders: true,
    legacyHeaders: false,
    skip,
    keyGenerator,
  });
};

/**
 * General API rate limiter - 100 requests per 15 minutes
 */
export const generalLimiter = createRateLimiter({
  windowMs: 15 * 60 * 1000,
  max: 100,
  message: 'Too many requests from this IP, please try again after 15 minutes',
});

/**
 * Strict rate limiter for sensitive operations - 10 requests per 15 minutes
 */
export const strictLimiter = createRateLimiter({
  windowMs: 15 * 60 * 1000,
  max: 10,
  message: 'Too many attempts, please try again later',
});

/**
 * Auth rate limiter - 5 attempts per 15 minutes
 */
export const authLimiter = createRateLimiter({
  windowMs: 15 * 60 * 1000,
  max: 5,
  message: 'Too many authentication attempts, please try again after 15 minutes',
});

/**
 * Profile creation rate limiter - 3 profiles per hour
 */
export const profileCreationLimiter = createRateLimiter({
  windowMs: 60 * 60 * 1000,
  max: 3,
  message: 'Too many profile creation attempts, please try again later',
});

/**
 * Discovery rate limiter - 60 requests per minute
 */
export const discoveryLimiter = createRateLimiter({
  windowMs: 60 * 1000,
  max: 60,
  message: 'Too many discovery requests, please slow down',
});

/**
 * Message rate limiter - 30 messages per minute
 */
export const messageLimiter = createRateLimiter({
  windowMs: 60 * 1000,
  max: 30,
  message: 'Too many messages, please slow down',
});

/**
 * Upload rate limiter - 10 uploads per hour
 */
export const uploadLimiter = createRateLimiter({
  windowMs: 60 * 60 * 1000,
  max: 10,
  message: 'Too many uploads, please try again later',
});
