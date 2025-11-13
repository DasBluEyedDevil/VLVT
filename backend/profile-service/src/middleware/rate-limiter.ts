import rateLimit from 'express-rate-limit';
import logger from '../utils/logger';

// Note: Using memory store for rate limiting
// For production with multiple instances, configure Redis via REDIS_URL
// and install rate-limit-redis package
if (process.env.REDIS_URL) {
  logger.warn('REDIS_URL is set but Redis integration is disabled. Using memory store for rate limiting.');
  logger.warn('To enable Redis: npm install rate-limit-redis redis and update rate-limiter.ts');
} else {
  logger.info('Using memory store for rate limiting (sufficient for single-instance deployment)');
}

// General API rate limiter (100 requests per 15 minutes per IP)
export const generalLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100,
  message: 'Too many requests from this IP, please try again later',
  standardHeaders: true, // Return rate limit info in the `RateLimit-*` headers
  legacyHeaders: false, // Disable the `X-RateLimit-*` headers
  handler: (req, res) => {
    logger.warn('Rate limit exceeded', {
      ip: req.ip,
      path: req.path,
      limiter: 'general'
    });
    res.status(429).json({
      success: false,
      error: 'Too many requests from this IP, please try again later'
    });
  }
});

// Authentication rate limiter (10 requests per 15 minutes per IP)
export const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 10,
  message: 'Too many authentication attempts, please try again later',
  standardHeaders: true,
  legacyHeaders: false,
  handler: (req, res) => {
    logger.warn('Auth rate limit exceeded', {
      ip: req.ip,
      path: req.path,
      limiter: 'auth'
    });
    res.status(429).json({
      success: false,
      error: 'Too many authentication attempts, please try again later'
    });
  }
});

// Token verification rate limiter (100 requests per 15 minutes per IP)
export const verifyLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100,
  message: 'Too many verification requests, please try again later',
  standardHeaders: true,
  legacyHeaders: false,
  handler: (req, res) => {
    logger.warn('Verify rate limit exceeded', {
      ip: req.ip,
      path: req.path,
      limiter: 'verify'
    });
    res.status(429).json({
      success: false,
      error: 'Too many verification requests, please try again later'
    });
  }
});

// Strict rate limiter for sensitive operations (5 requests per 15 minutes per IP)
export const strictLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 5,
  message: 'Too many requests for this sensitive operation, please try again later',
  standardHeaders: true,
  legacyHeaders: false,
  handler: (req, res) => {
    logger.warn('Strict rate limit exceeded', {
      ip: req.ip,
      path: req.path,
      limiter: 'strict'
    });
    res.status(429).json({
      success: false,
      error: 'Too many requests for this sensitive operation, please try again later'
    });
  }
});

// Profile creation rate limiter (5 profile creations per day per IP)
export const profileCreationLimiter = rateLimit({
  windowMs: 24 * 60 * 60 * 1000, // 24 hours
  max: 5,
  message: 'Too many profile creations from this IP, please try again tomorrow',
  standardHeaders: true,
  legacyHeaders: false,
  handler: (req, res) => {
    logger.warn('Profile creation rate limit exceeded', {
      ip: req.ip,
      path: req.path,
      limiter: 'profile-creation'
    });
    res.status(429).json({
      success: false,
      error: 'Too many profile creations from this IP, please try again tomorrow'
    });
  }
});

// Discovery rate limiter (200 requests per 15 minutes per IP)
export const discoveryLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 200,
  message: 'Too many discovery requests, please try again later',
  standardHeaders: true,
  legacyHeaders: false,
  handler: (req, res) => {
    logger.warn('Discovery rate limit exceeded', {
      ip: req.ip,
      path: req.path,
      limiter: 'discovery'
    });
    res.status(429).json({
      success: false,
      error: 'Too many discovery requests, please try again later'
    });
  }
});
