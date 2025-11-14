/**
 * Firebase Cloud Messaging Service
 * Handles sending push notifications to users
 */

import * as admin from 'firebase-admin';
import { Pool } from 'pg';
import logger from '../utils/logger';

// Initialize Firebase Admin SDK
let firebaseInitialized = false;

/**
 * Initialize Firebase Admin SDK
 * Requires FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, and FIREBASE_PRIVATE_KEY env vars
 */
export const initializeFirebase = (): void => {
  if (firebaseInitialized) {
    logger.info('Firebase Admin already initialized');
    return;
  }

  try {
    // Check if required environment variables are set
    const projectId = process.env.FIREBASE_PROJECT_ID;
    const clientEmail = process.env.FIREBASE_CLIENT_EMAIL;
    const privateKey = process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n');

    if (!projectId || !clientEmail || !privateKey) {
      logger.warn('Firebase credentials not configured - push notifications disabled', {
        hasProjectId: !!projectId,
        hasClientEmail: !!clientEmail,
        hasPrivateKey: !!privateKey
      });
      return;
    }

    admin.initializeApp({
      credential: admin.credential.cert({
        projectId,
        clientEmail,
        privateKey
      })
    });

    firebaseInitialized = true;
    logger.info('Firebase Admin SDK initialized successfully');
  } catch (error) {
    logger.error('Failed to initialize Firebase Admin SDK', { error });
    // Don't throw - allow app to continue without push notifications
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
    logger.error('Failed to deactivate FCM token', { token, error });
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
  if (!isFirebaseReady()) {
    logger.debug('Firebase not initialized - skipping push notification');
    return;
  }

  try {
    const tokens = await getUserTokens(pool, recipientUserId);

    if (tokens.length === 0) {
      logger.debug('No active FCM tokens for user', { userId: recipientUserId });
      return;
    }

    // Truncate message preview if too long
    const preview = messageText.length > 100
      ? messageText.substring(0, 97) + '...'
      : messageText;

    const message: admin.messaging.MulticastMessage = {
      tokens,
      notification: {
        title: `New message from ${senderName}`,
        body: preview
      },
      data: {
        type: 'message',
        matchId: matchId.toString(),
        senderId: recipientUserId,
        senderName,
        click_action: 'FLUTTER_NOTIFICATION_CLICK'
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            badge: 1,
            contentAvailable: true
          }
        }
      },
      android: {
        priority: 'high',
        notification: {
          sound: 'default',
          channelId: 'messages',
          priority: 'high'
        }
      }
    };

    const response = await admin.messaging().sendEachForMulticast(message);

    logger.info('Message notification sent', {
      recipientId: recipientUserId,
      successCount: response.successCount,
      failureCount: response.failureCount,
      totalTokens: tokens.length
    });

    // Handle failed tokens
    if (response.failureCount > 0) {
      response.responses.forEach((resp, idx) => {
        if (!resp.success) {
          const errorCode = resp.error?.code;

          // Deactivate invalid tokens
          if (errorCode === 'messaging/invalid-registration-token' ||
              errorCode === 'messaging/registration-token-not-registered') {
            deactivateToken(pool, tokens[idx]);
          }

          logger.warn('Failed to send notification to token', {
            tokenIndex: idx,
            errorCode,
            errorMessage: resp.error?.message
          });
        }
      });
    }
  } catch (error) {
    logger.error('Failed to send message notification', { recipientUserId, error });
  }
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
  if (!isFirebaseReady()) {
    logger.debug('Firebase not initialized - skipping push notification');
    return;
  }

  try {
    const tokens = await getUserTokens(pool, recipientUserId);

    if (tokens.length === 0) {
      logger.debug('No active FCM tokens for user', { userId: recipientUserId });
      return;
    }

    const message: admin.messaging.MulticastMessage = {
      tokens,
      notification: {
        title: `🎉 It's a match!`,
        body: `You and ${matchedUserName} liked each other!`
      },
      data: {
        type: 'match',
        matchId: matchId.toString(),
        matchedUserName,
        click_action: 'FLUTTER_NOTIFICATION_CLICK'
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            badge: 1,
            contentAvailable: true
          }
        }
      },
      android: {
        priority: 'high',
        notification: {
          sound: 'default',
          channelId: 'matches',
          priority: 'high'
        }
      }
    };

    const response = await admin.messaging().sendEachForMulticast(message);

    logger.info('Match notification sent', {
      recipientId: recipientUserId,
      successCount: response.successCount,
      failureCount: response.failureCount,
      totalTokens: tokens.length
    });

    // Handle failed tokens
    if (response.failureCount > 0) {
      response.responses.forEach((resp, idx) => {
        if (!resp.success) {
          const errorCode = resp.error?.code;

          // Deactivate invalid tokens
          if (errorCode === 'messaging/invalid-registration-token' ||
              errorCode === 'messaging/registration-token-not-registered') {
            deactivateToken(pool, tokens[idx]);
          }

          logger.warn('Failed to send notification to token', {
            tokenIndex: idx,
            errorCode,
            errorMessage: resp.error?.message
          });
        }
      });
    }
  } catch (error) {
    logger.error('Failed to send match notification', { recipientUserId, error });
  }
};

/**
 * Register a new FCM token for a user
 */
export const registerFCMToken = async (
  pool: Pool,
  userId: string,
  token: string,
  deviceType: 'ios' | 'android' | 'web',
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
      tokenPreview: token.substring(0, 20) + '...'
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
      rowsAffected: result.rowCount
    });
  } catch (error) {
    logger.error('Failed to unregister FCM token', { userId, error });
    throw error;
  }
};
