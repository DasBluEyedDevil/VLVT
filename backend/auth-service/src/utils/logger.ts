import winston from 'winston';
import * as Sentry from '@sentry/node';

// PII redaction format function
const redactEmail = (email: string): string => {
  if (!email || !email.includes('@')) return email;
  const [local, domain] = email.split('@');
  if (local.length <= 2) return `${local[0]}***@${domain}`;
  return `${local[0]}***${local[local.length - 1]}@${domain}`;
};

// List of sensitive field names that should be redacted
const SENSITIVE_FIELDS = [
  'token', 'idToken', 'identityToken', 'authorization',
  'accessToken', 'refreshToken', 'tempToken', 'resetToken',
  'verificationToken', 'password', 'passwordHash', 'password_hash',
  'newPassword', 'currentPassword', 'secret', 'apiKey', 'api_key',
  'bearer', 'jwt', 'code', 'clientSecret', 'client_secret'
];

// Recursively redact sensitive fields in objects
const redactObject = (obj: any, depth = 0): any => {
  if (depth > 5 || !obj || typeof obj !== 'object') return obj;

  if (Array.isArray(obj)) {
    return obj.map(item => redactObject(item, depth + 1));
  }

  const redacted: any = {};
  for (const [key, value] of Object.entries(obj)) {
    const lowerKey = key.toLowerCase();
    if (SENSITIVE_FIELDS.some(field => lowerKey.includes(field.toLowerCase()))) {
      redacted[key] = '[REDACTED]';
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

// Custom format to redact sensitive information
const redactSensitiveInfo = winston.format((info) => {
  // Redact known sensitive fields
  for (const field of SENSITIVE_FIELDS) {
    if (info[field]) {
      info[field] = '[REDACTED]';
    }
  }

  // Redact email addresses
  if (info.email && typeof info.email === 'string') {
    info.email = redactEmail(info.email);
  }

  // Recursively redact sensitive data in nested objects (like req.body)
  if (info.body && typeof info.body === 'object') {
    info.body = redactObject(info.body);
  }

  if (info.meta && typeof info.meta === 'object') {
    info.meta = redactObject(info.meta);
  }

  // If the message contains email patterns, redact them
  if (typeof info.message === 'string' && info.message.includes('@')) {
    const emailRegex = /[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/g;
    info.message = info.message.replace(emailRegex, (match) => redactEmail(match));
  }

  return info;
});

// Create logger instance
const transports: any[] = [];

// In test environment, don't write to files (use memory transport or console only)
if (process.env.NODE_ENV !== 'test') {
  transports.push(
    // Error logs go to error.log
    new winston.transports.File({
      filename: 'logs/error.log',
      level: 'error',
      maxsize: 10485760, // 10MB
      maxFiles: 5,
    }),
    // All logs go to combined.log
    new winston.transports.File({
      filename: 'logs/combined.log',
      maxsize: 10485760, // 10MB
      maxFiles: 5,
    })
  );
}

const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.combine(
    winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
    winston.format.errors({ stack: true }),
    redactSensitiveInfo(),
    winston.format.json()
  ),
  defaultMeta: { service: 'auth-service' },
  transports,
  silent: process.env.NODE_ENV === 'test', // Silence logs in test mode
});

// If we're not in production, also log to console with colorized output
if (process.env.NODE_ENV !== 'production') {
  logger.add(new winston.transports.Console({
    format: winston.format.combine(
      winston.format.colorize(),
      winston.format.timestamp({ format: 'HH:mm:ss' }),
      winston.format.printf(({ timestamp, level, message, service, ...meta }) => {
        const metaStr = Object.keys(meta).length ? JSON.stringify(meta, null, 2) : '';
        return `${timestamp} [${service}] ${level}: ${message} ${metaStr}`;
      })
    ),
  }));
}

// Integrate with Sentry for error-level logs
const originalError = logger.error.bind(logger);
logger.error = (message: any, ...meta: any[]): any => {
  // Log to winston
  const result = originalError(message, ...meta);

  // Also send to Sentry if configured
  if (process.env.SENTRY_DSN) {
    if (message instanceof Error) {
      Sentry.captureException(message);
    } else {
      Sentry.captureMessage(String(message), 'error');
    }
  }

  return result;
};

export default logger;
