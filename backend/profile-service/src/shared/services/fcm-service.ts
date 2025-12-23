/**
 * Shared Firebase Cloud Messaging Service
 * Centralizes push notification handling for all VLVT microservices
 */

import * as admin from 'firebase-admin';
import { Pool } from 'pg';
import type { PushNotificationOptions, DeviceType } from '../types/api';

// Logger interface for dependency injection
interface Logger {
  info: (message: string, meta?: object) => void;
  warn: (message: string, meta?: object) => void;
  error: (message: string, meta?: object) => void;
  debug: (message: string, meta?: object) => void;
}

// Module-level state
let firebaseInitialized = false;
let logger: Logger = console as unknown as Logger;

/**
 * Set custom logger for FCM service
 */
export const setFCMLogger = (customLogger: Logger): void => {
  logger = customLogger;
};

/**
 * Initialize Firebase Admin SDK
 * Requires FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, and FIREBASE_PRIVATE_KEY env vars
 */
export const initializeFirebase = (): boolean => {
  if (firebaseInitialized) {
    logger.info('Firebase Admin already initialized');
    return true;
  }

  try {
    const projectId = process.env.FIREBASE_PROJECT_ID;
    const clientEmail = process.env.FIREBASE_CLIENT_EMAIL;
    const privateKey = process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n');

    if (!projectId || !clientEmail || !privateKey) {
      logger.warn('Firebase credentials not configured - push notifications disabled', {
        hasProjectId: !!projectId,
        hasClientEmail: !!clientEmail,
        hasPrivateKey: !!privateKey,
      });
      return false;
    }

    admin.initializeApp({
      credential: admin.credential.cert({
        projectId,
        clientEmail,
        privateKey,
      }),
    });

    firebaseInitialized = true;
    logger.info('Firebase Admin SDK initialized successfully');
    return true;
  } catch (error) {
    logger.error('Failed to initialize Firebase Admin SDK', { error });
    return false;
  }
};

/**
 * Check if Firebase is initialized and ready
 */
export const isFirebaseReady = (): boolean => {
  return firebaseInitialized;
};

/**
 * Get active FCM tokens for a user
 */
const getUserTokens = async (pool: Pool, userId: string): Promise<string[]> => {
  try {
    const result = await pool.query(
      'SELECT token FROM fcm_tokens WHERE user_id = $1 AND is_active = true',
      [userId]
    );
    return result.rows.map(row => row.token);
  } catch (error) {
    logger.error('Failed to fetch user FCM tokens', { userId, error });
    return [];
  }
};

/**
 * Mark FCM token as inactive
 */
const deactivateToken = async (pool: Pool, token: string): Promise<void> => {
  try {
    await pool.query(
      'UPDATE fcm_tokens SET is_active = false WHERE token = $1',
      [token]
    );
    logger.info('Deactivated invalid FCM token', { token: token.substring(0, 20) + '...' });
  } catch (error) {
    logger.error('Failed to deactivate FCM token', { error });
  }
};

/**
 * Handle failed tokens from multicast response
 */
const handleFailedTokens = async (
  pool: Pool,
  tokens: string[],
  response: admin.messaging.BatchResponse
): Promise<void> => {
  if (response.failureCount === 0) return;

  response.responses.forEach((resp, idx) => {
    if (!resp.success) {
      const errorCode = resp.error?.code;

      // Deactivate invalid tokens
      if (
        errorCode === 'messaging/invalid-registration-token' ||
        errorCode === 'messaging/registration-token-not-registered'
      ) {
        deactivateToken(pool, tokens[idx]);
      }

      logger.warn('Failed to send notification to token', {
        tokenIndex: idx,
        errorCode,
        errorMessage: resp.error?.message,
      });
    }
  });
};

/**
 * Build multicast message with platform-specific configuration
 */
const buildMulticastMessage = (
  tokens: string[],
  title: string,
  body: string,
  data: Record<string, string>,
  channelId = 'default'
): admin.messaging.MulticastMessage => {
  return {
    tokens,
    notification: { title, body },
    data: {
      ...data,
      click_action: 'FLUTTER_NOTIFICATION_CLICK',
    },
    apns: {
      payload: {
        aps: {
          sound: 'default',
          badge: 1,
          contentAvailable: true,
        },
      },
    },
    android: {
      priority: 'high',
      notification: {
        sound: 'default',
        channelId,
        priority: 'high',
      },
    },
  };
};

/**
 * Send a push notification
 */
export const sendPushNotification = async (
  pool: Pool,
  options: PushNotificationOptions
): Promise<boolean> => {
  if (!isFirebaseReady()) {
    logger.debug('Firebase not initialized - skipping push notification');
    return false;
  }

  try {
    const tokens = await getUserTokens(pool, options.userId);

    if (tokens.length === 0) {
      logger.debug('No active FCM tokens for user', { userId: options.userId });
      return false;
    }

    const message = buildMulticastMessage(
      tokens,
      options.title,
      options.body,
      options.data || {},
      options.channelId
    );

    const response = await admin.messaging().sendEachForMulticast(message);

    logger.info('Push notification sent', {
      userId: options.userId,
      successCount: response.successCount,
      failureCount: response.failureCount,
      totalTokens: tokens.length,
    });

    await handleFailedTokens(pool, tokens, response);

    return response.successCount > 0;
  } catch (error) {
    logger.error('Failed to send push notification', { userId: options.userId, error });
    return false;
  }
};

/**
 * Send a push notification for a new message
 */
export const sendMessageNotification = async (
  pool: Pool,
  recipientUserId: string,
  senderName: string,
  messageText: string,
  matchId: string
): Promise<void> => {
  // Truncate message preview if too long
  const preview = messageText.length > 100
    ? messageText.substring(0, 97) + '...'
    : messageText;

  await sendPushNotification(pool, {
    userId: recipientUserId,
    title: `New message from ${senderName}`,
    body: preview,
    data: {
      type: 'message',
      matchId: matchId.toString(),
      senderName,
    },
    channelId: 'messages',
  });
};

/**
 * Send a push notification for a new match
 */
export const sendMatchNotification = async (
  pool: Pool,
  recipientUserId: string,
  matchedUserName: string,
  matchId: string
): Promise<void> => {
  await sendPushNotification(pool, {
    userId: recipientUserId,
    title: "🎉 It's a match!",
    body: `You and ${matchedUserName} liked each other!`,
    data: {
      type: 'match',
      matchId: matchId.toString(),
      matchedUserName,
    },
    channelId: 'matches',
  });
};

/**
 * Send a push notification for typing indicator (optional, low priority)
 */
export const sendTypingNotification = async (
  pool: Pool,
  recipientUserId: string,
  senderName: string,
  matchId: string
): Promise<void> => {
  await sendPushNotification(pool, {
    userId: recipientUserId,
    title: '',
    body: `${senderName} is typing...`,
    data: {
      type: 'typing',
      matchId: matchId.toString(),
      senderName,
      silent: 'true',
    },
  });
};

/**
 * Register a new FCM token for a user
 */
export const registerFCMToken = async (
  pool: Pool,
  userId: string,
  token: string,
  deviceType: DeviceType,
  deviceId?: string
): Promise<void> => {
  try {
    await pool.query(
      `INSERT INTO fcm_tokens (user_id, token, device_type, device_id, is_active, updated_at, last_used_at)
       VALUES ($1, $2, $3, $4, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
       ON CONFLICT (user_id, token)
       DO UPDATE SET
         device_type = EXCLUDED.device_type,
         device_id = EXCLUDED.device_id,
         is_active = true,
         updated_at = CURRENT_TIMESTAMP,
         last_used_at = CURRENT_TIMESTAMP`,
      [userId, token, deviceType, deviceId || null]
    );

    logger.info('FCM token registered', {
      userId,
      deviceType,
      tokenPreview: token.substring(0, 20) + '...',
    });
  } catch (error) {
    logger.error('Failed to register FCM token', { userId, deviceType, error });
    throw error;
  }
};

/**
 * Unregister (deactivate) an FCM token
 */
export const unregisterFCMToken = async (
  pool: Pool,
  userId: string,
  token: string
): Promise<void> => {
  try {
    const result = await pool.query(
      'UPDATE fcm_tokens SET is_active = false WHERE user_id = $1 AND token = $2',
      [userId, token]
    );

    logger.info('FCM token unregistered', {
      userId,
      tokenPreview: token.substring(0, 20) + '...',
      rowsAffected: result.rowCount,
    });
  } catch (error) {
    logger.error('Failed to unregister FCM token', { userId, error });
    throw error;
  }
};

/**
 * Deactivate all tokens for a user (e.g., on logout)
 */
export const deactivateAllUserTokens = async (
  pool: Pool,
  userId: string
): Promise<void> => {
  try {
    const result = await pool.query(
      'UPDATE fcm_tokens SET is_active = false WHERE user_id = $1',
      [userId]
    );

    logger.info('All FCM tokens deactivated for user', {
      userId,
      rowsAffected: result.rowCount,
    });
  } catch (error) {
    logger.error('Failed to deactivate all FCM tokens', { userId, error });
    throw error;
  }
};
