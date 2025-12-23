/**
 * Shared API types for VLVT microservices
 */

export interface ApiResponse<T = unknown> {
  success: boolean;
  data?: T;
  error?: string;
  message?: string;
  details?: unknown;
}

export interface PaginatedResponse<T> extends ApiResponse<T[]> {
  total: number;
  page: number;
  limit: number;
  hasMore: boolean;
}

export interface PushNotificationOptions {
  userId: string;
  title: string;
  body: string;
  data?: Record<string, string>;
  channelId?: string;
}

export interface EmailOptions {
  to: string;
  subject: string;
  html: string;
  text?: string;
}

export type DeviceType = 'ios' | 'android' | 'web';
