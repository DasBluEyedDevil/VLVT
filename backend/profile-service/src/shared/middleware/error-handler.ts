/**
 * Shared Error Handling Middleware
 * Centralizes error handling for all VLVT microservices
 */

import { Request, Response, NextFunction, ErrorRequestHandler } from 'express';
import * as Sentry from '@sentry/node';
import type winston from 'winston';

export interface ErrorHandlerOptions {
  /** Logger instance for error logging */
  logger?: winston.Logger | Console;
  /** Enable Sentry error reporting */
  enableSentry?: boolean;
  /** Include stack traces in responses (dev only) */
  includeStack?: boolean;
}

/**
 * Custom API error class with status code
 */
export class ApiError extends Error {
  statusCode: number;
  details?: unknown;

  constructor(message: string, statusCode = 500, details?: unknown) {
    super(message);
    this.name = 'ApiError';
    this.statusCode = statusCode;
    this.details = details;
  }

  static badRequest(message: string, details?: unknown): ApiError {
    return new ApiError(message, 400, details);
  }

  static unauthorized(message = 'Unauthorized'): ApiError {
    return new ApiError(message, 401);
  }

  static forbidden(message = 'Forbidden'): ApiError {
    return new ApiError(message, 403);
  }

  static notFound(message = 'Not found'): ApiError {
    return new ApiError(message, 404);
  }

  static conflict(message: string, details?: unknown): ApiError {
    return new ApiError(message, 409, details);
  }

  static tooManyRequests(message = 'Too many requests'): ApiError {
    return new ApiError(message, 429);
  }

  static internal(message = 'Internal server error'): ApiError {
    return new ApiError(message, 500);
  }
}

/**
 * Create an error handling middleware
 */
export const createErrorHandler = (options: ErrorHandlerOptions = {}): ErrorRequestHandler => {
  const {
    logger = console,
    enableSentry = !!process.env.SENTRY_DSN,
    includeStack = process.env.NODE_ENV !== 'production',
  } = options;

  return (err: Error | ApiError, req: Request, res: Response, _next: NextFunction): void => {
    // Determine status code
    const statusCode = 'statusCode' in err ? err.statusCode : 500;
    const details = 'details' in err ? err.details : undefined;

    // Log the error
    logger.error('Request error', {
      error: err.message,
      stack: err.stack,
      path: req.path,
      method: req.method,
      statusCode,
      userId: req.user?.userId,
    });

    // Report to Sentry for server errors
    if (enableSentry && statusCode >= 500) {
      Sentry.captureException(err, {
        extra: {
          path: req.path,
          method: req.method,
          userId: req.user?.userId,
        },
      });
    }

    // Build response
    const response: Record<string, unknown> = {
      success: false,
      error: err.message || 'Internal server error',
    };

    if (details) {
      response.details = details;
    }

    if (includeStack && err.stack) {
      response.stack = err.stack;
    }

    res.status(statusCode).json(response);
  };
};

/**
 * Default error handler
 */
export const errorHandler = createErrorHandler();

/**
 * 404 Not Found handler for unmatched routes
 */
export const notFoundHandler = (req: Request, res: Response): void => {
  res.status(404).json({
    success: false,
    error: `Route ${req.method} ${req.path} not found`,
  });
};

/**
 * Async handler wrapper to catch promise rejections
 */
export const asyncHandler = <T>(
  fn: (req: Request, res: Response, next: NextFunction) => Promise<T>
) => {
  return (req: Request, res: Response, next: NextFunction): void => {
    Promise.resolve(fn(req, res, next)).catch(next);
  };
};
