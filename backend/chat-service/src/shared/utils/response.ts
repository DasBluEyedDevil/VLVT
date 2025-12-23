/**
 * Standardized API Response Utilities
 * Ensures consistent response format across all VLVT microservices
 */

import { Response } from 'express';
import type { ApiResponse, PaginatedResponse } from '../types/api';

/**
 * Send a success response
 */
export const sendSuccess = <T>(
  res: Response,
  data?: T,
  statusCode = 200
): Response => {
  const response: ApiResponse<T> = {
    success: true,
  };

  if (data !== undefined) {
    response.data = data;
  }

  return res.status(statusCode).json(response);
};

/**
 * Send a success response with a custom message
 */
export const sendSuccessMessage = (
  res: Response,
  message: string,
  statusCode = 200
): Response => {
  return res.status(statusCode).json({
    success: true,
    message,
  });
};

/**
 * Send an error response
 */
export const sendError = (
  res: Response,
  error: string,
  statusCode = 500,
  details?: unknown
): Response => {
  const response: ApiResponse = {
    success: false,
    error,
  };

  if (details !== undefined) {
    response.details = details;
  }

  return res.status(statusCode).json(response);
};

/**
 * Send a paginated response
 */
export const sendPaginated = <T>(
  res: Response,
  data: T[],
  options: {
    total: number;
    page: number;
    limit: number;
  }
): Response => {
  const { total, page, limit } = options;
  const hasMore = page * limit < total;

  const response: PaginatedResponse<T> = {
    success: true,
    data,
    total,
    page,
    limit,
    hasMore,
  };

  return res.status(200).json(response);
};

/**
 * Common error responses
 */
export const errors = {
  badRequest: (res: Response, message = 'Bad request', details?: unknown) =>
    sendError(res, message, 400, details),

  unauthorized: (res: Response, message = 'Unauthorized') =>
    sendError(res, message, 401),

  forbidden: (res: Response, message = 'Forbidden') =>
    sendError(res, message, 403),

  notFound: (res: Response, message = 'Not found') =>
    sendError(res, message, 404),

  conflict: (res: Response, message = 'Conflict', details?: unknown) =>
    sendError(res, message, 409, details),

  tooManyRequests: (res: Response, message = 'Too many requests') =>
    sendError(res, message, 429),

  internal: (res: Response, message = 'Internal server error') =>
    sendError(res, message, 500),
};
