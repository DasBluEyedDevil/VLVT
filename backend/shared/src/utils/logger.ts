/**
 * Shared Winston Logger with PII Redaction and Sentry Integration
 * Centralizes logging configuration for all VLVT microservices
 */

import winston from 'winston';
import * as Sentry from '@sentry/node';

export interface LoggerOptions {
  /** Service name for log metadata */
  service: string;
  /** Log level (defaults to LOG_LEVEL env or 'info') */
  level?: string;
  /** Enable Sentry integration */
  enableSentry?: boolean;
  /** Custom Sentry DSN (defaults to SENTRY_DSN env) */
  sentryDsn?: string;
  /** Silent mode for testing */
  silent?: boolean;
}

// List of sensitive field names that should be redacted
const SENSITIVE_FIELDS = [
  'token', 'idToken', 'identityToken', 'authorization',
  'accessToken', 'refreshToken', 'tempToken', 'resetToken',
  'verificationToken', 'password', 'passwordHash', 'password_hash',
  'newPassword', 'currentPassword', 'secret', 'apiKey', 'api_key',
  'bearer', 'jwt', 'code', 'clientSecret', 'client_secret',
  'privateKey', 'private_key', 'creditCard', 'ssn',
];

/**
 * Redact email addresses for privacy
 */
const redactEmail = (email: string): string => {
  if (!email || !email.includes('@')) return email;
  const [local, domain] = email.split('@');
  if (local.length <= 2) return `${local[0]}***@${domain}`;
  return `${local[0]}***${local[local.length - 1]}@${domain}`;
};

/**
 * Recursively redact sensitive fields in objects
 */
const redactObject = (obj: unknown, depth = 0): unknown => {
  if (depth > 5 || !obj || typeof obj !== 'object') return obj;

  if (Array.isArray(obj)) {
    return obj.map(item => redactObject(item, depth + 1));
  }

  const redacted: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(obj as Record<string, unknown>)) {
    const lowerKey = key.toLowerCase();
    if (SENSITIVE_FIELDS.some(field => lowerKey.includes(field.toLowerCase()))) {
      redacted[key] = '[REDACTED]';
    } else if (key === 'photos' && Array.isArray(value)) {
      // Redact photo URLs, only log count
      redacted[key] = `[${value.length} photos]`;
    } else if (typeof value === 'object' && value !== null) {
      redacted[key] = redactObject(value, depth + 1);
    } else if (typeof value === 'string' && value.includes('@')) {
      // Redact email addresses in string values
      redacted[key] = redactEmail(value);
    } else {
      redacted[key] = value;
    }
  }
  return redacted;
};

/**
 * Winston format to redact sensitive information
 */
const redactSensitiveInfo = winston.format((info) => {
  // Redact known sensitive fields at top level
  for (const field of SENSITIVE_FIELDS) {
    if (info[field]) {
      info[field] = '[REDACTED]';
    }
  }

  // Redact email addresses
  if (info.email && typeof info.email === 'string') {
    info.email = redactEmail(info.email);
  }

  // Recursively redact sensitive data in nested objects
  if (info.body && typeof info.body === 'object') {
    info.body = redactObject(info.body);
  }

  if (info.meta && typeof info.meta === 'object') {
    info.meta = redactObject(info.meta);
  }

  // Redact emails in message strings
  if (typeof info.message === 'string' && info.message.includes('@')) {
    const emailRegex = /[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/g;
    info.message = info.message.replace(emailRegex, (match) => redactEmail(match));
  }

  return info;
});

/**
 * Create a configured logger instance
 */
export const createLogger = (options: LoggerOptions): winston.Logger => {
  const {
    service,
    level = process.env.LOG_LEVEL || 'info',
    enableSentry = !!process.env.SENTRY_DSN,
    sentryDsn = process.env.SENTRY_DSN,
    silent = process.env.NODE_ENV === 'test',
  } = options;

  const transports: winston.transport[] = [];

  // File transports for non-test environments
  if (process.env.NODE_ENV !== 'test') {
    transports.push(
      new winston.transports.File({
        filename: 'logs/error.log',
        level: 'error',
        maxsize: 10485760, // 10MB
        maxFiles: 5,
      }),
      new winston.transports.File({
        filename: 'logs/combined.log',
        maxsize: 10485760, // 10MB
        maxFiles: 5,
      })
    );
  }

  const logger = winston.createLogger({
    level,
    format: winston.format.combine(
      winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
      winston.format.errors({ stack: true }),
      redactSensitiveInfo(),
      winston.format.json()
    ),
    defaultMeta: { service },
    transports,
    silent,
  });

  // Console transport for non-production environments
  if (process.env.NODE_ENV !== 'production') {
    logger.add(new winston.transports.Console({
      format: winston.format.combine(
        winston.format.colorize(),
        winston.format.timestamp({ format: 'HH:mm:ss' }),
        winston.format.printf(({ timestamp, level, message, service: svc, ...meta }) => {
          const metaStr = Object.keys(meta).length ? JSON.stringify(meta, null, 2) : '';
          return `${timestamp} [${svc}] ${level}: ${message} ${metaStr}`;
        })
      ),
    }));
  }

  // Integrate with Sentry for error-level logs
  if (enableSentry && sentryDsn) {
    const originalError = logger.error.bind(logger);
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    logger.error = (message: any, ...meta: any[]): winston.Logger => {
      // Log to winston
      const result = originalError(message, ...meta);

      // Also send to Sentry
      if (message instanceof Error) {
        Sentry.captureException(message);
      } else {
        Sentry.captureMessage(String(message), 'error');
      }

      return result;
    };
  }

  return logger;
};

/**
 * Default logger for quick usage (service name from SERVICE_NAME env or 'vlvt')
 */
export const defaultLogger = createLogger({
  service: process.env.SERVICE_NAME || 'vlvt',
});

export default createLogger;
