/**
 * Subscription Middleware
 * Enforces subscription limits on backend to prevent client-side bypass
 */

import { Request, Response, NextFunction } from 'express';
import { Pool } from 'pg';
import logger from '../utils/logger';

interface SubscriptionStatus {
  isPremium: boolean;
  expiresAt?: Date;
}

/**
 * Check if user has active premium subscription
 */
async function checkPremiumStatus(pool: Pool, userId: string): Promise<SubscriptionStatus> {
  try {
    // Query user_subscriptions table for active subscription
    const result = await pool.query(
      `SELECT is_active, expires_at
       FROM user_subscriptions
       WHERE user_id = $1
         AND is_active = true
         AND (expires_at IS NULL OR expires_at > NOW())
       ORDER BY expires_at DESC NULLS FIRST
       LIMIT 1`,
      [userId]
    );

    if (result.rows.length > 0) {
      return {
        isPremium: true,
        expiresAt: result.rows[0].expires_at
      };
    }

    return { isPremium: false };
  } catch (error) {
    logger.error('Failed to check premium status', { error, userId });
    // Fail open - if we can't check, allow the action (prevents service disruption)
    return { isPremium: true };
  }
}

/**
 * Count user actions today (likes or messages)
 */
async function countTodayActions(
  pool: Pool,
  userId: string,
  actionType: 'likes' | 'messages'
): Promise<number> {
  try {
    let query: string;

    if (actionType === 'likes') {
      query = `
        SELECT COUNT(*) as count
        FROM swipes
        WHERE user_id = $1
          AND action = 'like'
          AND created_at::date = CURRENT_DATE
      `;
    } else {
      query = `
        SELECT COUNT(*) as count
        FROM messages
        WHERE sender_id = $1
          AND created_at::date = CURRENT_DATE
      `;
    }

    const result = await pool.query(query, [userId]);
    return parseInt(result.rows[0].count) || 0;
  } catch (error) {
    logger.error('Failed to count today actions', { error, userId, actionType });
    return 0; // Fail open
  }
}

/**
 * Subscription middleware factory
 */
export const createSubscriptionMiddleware = (pool: Pool) => {
  // Daily limits for free tier
  const FREE_DAILY_LIKES = 10;
  const FREE_DAILY_MESSAGES = 20;

  return {
    /**
     * Middleware: Check if user can like (for swipe/like endpoints)
     */
    canLike: async (req: Request, res: Response, next: NextFunction) => {
      try {
        const userId = req.user!.userId;

        // Check if premium user
        const subscription = await checkPremiumStatus(pool, userId);
        if (subscription.isPremium) {
          logger.debug('Premium user - unlimited likes', { userId });
          return next();
        }

        // Check daily limits for free tier
        const todayLikes = await countTodayActions(pool, userId, 'likes');

        if (todayLikes >= FREE_DAILY_LIKES) {
          logger.info('Daily like limit reached', { userId, todayLikes, limit: FREE_DAILY_LIKES });
          return res.status(429).json({
            success: false,
            error: 'Daily like limit reached',
            message: `You've used all ${FREE_DAILY_LIKES} likes for today. Upgrade to premium for unlimited likes!`,
            code: 'LIKE_LIMIT_REACHED',
            limit: FREE_DAILY_LIKES,
            used: todayLikes
          });
        }

        // User within limits - allow action
        next();
      } catch (error) {
        logger.error('Error in canLike middleware', { error });
        // Fail open - don't block user if middleware errors
        next();
      }
    },

    /**
     * Middleware: Check if user can send message
     */
    canMessage: async (req: Request, res: Response, next: NextFunction) => {
      try {
        const userId = req.user!.userId;

        // Check if premium user
        const subscription = await checkPremiumStatus(pool, userId);
        if (subscription.isPremium) {
          logger.debug('Premium user - unlimited messages', { userId });
          return next();
        }

        // Check daily limits for free tier
        const todayMessages = await countTodayActions(pool, userId, 'messages');

        if (todayMessages >= FREE_DAILY_MESSAGES) {
          logger.info('Daily message limit reached', { userId, todayMessages, limit: FREE_DAILY_MESSAGES });
          return res.status(429).json({
            success: false,
            error: 'Daily message limit reached',
            message: `You've used all ${FREE_DAILY_MESSAGES} messages for today. Upgrade to premium for unlimited messaging!`,
            code: 'MESSAGE_LIMIT_REACHED',
            limit: FREE_DAILY_MESSAGES,
            used: todayMessages
          });
        }

        // User within limits - allow action
        next();
      } catch (error) {
        logger.error('Error in canMessage middleware', { error });
        // Fail open - don't block user if middleware errors
        next();
      }
    },

    /**
     * Get user's current usage stats (for frontend display)
     */
    getUsageStats: async (req: Request, res: Response) => {
      try {
        const userId = req.user!.userId;

        const subscription = await checkPremiumStatus(pool, userId);
        const todayLikes = await countTodayActions(pool, userId, 'likes');
        const todayMessages = await countTodayActions(pool, userId, 'messages');

        res.json({
          success: true,
          isPremium: subscription.isPremium,
          expiresAt: subscription.expiresAt,
          usage: {
            likes: {
              used: todayLikes,
              limit: subscription.isPremium ? null : FREE_DAILY_LIKES,
              remaining: subscription.isPremium ? null : Math.max(0, FREE_DAILY_LIKES - todayLikes)
            },
            messages: {
              used: todayMessages,
              limit: subscription.isPremium ? null : FREE_DAILY_MESSAGES,
              remaining: subscription.isPremium ? null : Math.max(0, FREE_DAILY_MESSAGES - todayMessages)
            }
          }
        });
      } catch (error) {
        logger.error('Error getting usage stats', { error });
        res.status(500).json({ success: false, error: 'Failed to get usage stats' });
      }
    }
  };
};

export type SubscriptionMiddleware = ReturnType<typeof createSubscriptionMiddleware>;
