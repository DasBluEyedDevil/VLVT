/**
 * Socket.IO Message Event Handlers
 * Handles real-time messaging events
 */

import { Server as SocketServer } from 'socket.io';
import { Pool } from 'pg';
import { v4 as uuidv4 } from 'uuid';
import logger from '../utils/logger';
import { SocketWithAuth } from './auth-middleware';
import { sendMessageNotification } from '../services/fcm-service';

interface SendMessageData {
  matchId: string;
  text: string;
  tempId?: string; // Client-generated temporary ID
}

interface MarkReadData {
  matchId: string;
  messageIds?: string[]; // Specific messages to mark as read
}

interface TypingData {
  matchId: string;
  isTyping: boolean;
}

interface MessageResponse {
  id: string;
  matchId: string;
  senderId: string;
  text: string;
  status: string;
  createdAt: Date;
  tempId?: string;
}

/**
 * Setup message event handlers for a socket connection
 */
export const setupMessageHandlers = (io: SocketServer, socket: SocketWithAuth, pool: Pool) => {
  const userId = socket.userId!;

  logger.info('Setting up message handlers', { socketId: socket.id, userId });

  /**
   * Handle sending a new message
   */
  socket.on('send_message', async (data: SendMessageData, callback) => {
    try {
      const { matchId, text, tempId } = data;

      // Validate input
      if (!matchId || !text || text.trim().length === 0) {
        logger.warn('Invalid message data', { userId, matchId, hasText: !!text });
        return callback?.({ success: false, error: 'Invalid message data' });
      }

      if (text.length > 5000) {
        logger.warn('Message too long', { userId, matchId, length: text.length });
        return callback?.({ success: false, error: 'Message too long (max 5000 characters)' });
      }

      // Verify user is part of the match
      const matchCheck = await pool.query(
        'SELECT user_id_1, user_id_2 FROM matches WHERE id = $1',
        [matchId]
      );

      if (matchCheck.rows.length === 0) {
        logger.warn('Match not found', { userId, matchId });
        return callback?.({ success: false, error: 'Match not found' });
      }

      const match = matchCheck.rows[0];
      if (match.user_id_1 !== userId && match.user_id_2 !== userId) {
        logger.warn('Unauthorized message send attempt', { userId, matchId });
        return callback?.({ success: false, error: 'Unauthorized' });
      }

      // Create the message
      const messageId = uuidv4();
      const now = new Date();

      const result = await pool.query(
        `INSERT INTO messages (id, match_id, sender_id, text, status, created_at)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING id, match_id, sender_id, text, status, created_at`,
        [messageId, matchId, userId, text.trim(), 'sent', now]
      );

      const message = result.rows[0];
      const messageResponse: MessageResponse = {
        id: message.id,
        matchId: message.match_id,
        senderId: message.sender_id,
        text: message.text,
        status: message.status,
        createdAt: message.created_at,
        tempId
      };

      // Determine recipient
      const recipientId = match.user_id_1 === userId ? match.user_id_2 : match.user_id_1;

      // Emit to recipient if they're online
      io.to(`user:${recipientId}`).emit('new_message', messageResponse);

      // Update message status to delivered if recipient is online
      const recipientSockets = await io.in(`user:${recipientId}`).fetchSockets();
      if (recipientSockets.length > 0) {
        await pool.query(
          'UPDATE messages SET status = $1, delivered_at = $2 WHERE id = $3',
          ['delivered', new Date(), messageId]
        );
        messageResponse.status = 'delivered';
      } else {
        // Recipient is offline - send push notification
        // Get sender name for notification
        const senderProfileResult = await pool.query(
          'SELECT name FROM profiles WHERE id = $1',
          [userId]
        );

        if (senderProfileResult.rows.length > 0) {
          const senderName = senderProfileResult.rows[0].name;
          // Fire and forget - don't await
          sendMessageNotification(pool, recipientId, senderName, text, matchId).catch(err =>
            logger.error('Failed to send message push notification', { recipientId, error: err })
          );
        }
      }

      logger.info('Message sent', {
        messageId,
        matchId,
        senderId: userId,
        recipientId,
        delivered: recipientSockets.length > 0
      });

      // Send acknowledgment to sender
      callback?.({ success: true, message: messageResponse });
    } catch (error) {
      logger.error('Error sending message', {
        error: error instanceof Error ? error.message : 'Unknown error',
        userId,
        matchId: data.matchId
      });
      callback?.({ success: false, error: 'Failed to send message' });
    }
  });

  /**
   * Handle marking messages as read
   */
  socket.on('mark_read', async (data: MarkReadData, callback) => {
    try {
      const { matchId, messageIds } = data;

      // Verify user is part of the match
      const matchCheck = await pool.query(
        'SELECT user_id_1, user_id_2 FROM matches WHERE id = $1',
        [matchId]
      );

      if (matchCheck.rows.length === 0) {
        logger.warn('Match not found for mark_read', { userId, matchId });
        return callback?.({ success: false, error: 'Match not found' });
      }

      const match = matchCheck.rows[0];
      if (match.user_id_1 !== userId && match.user_id_2 !== userId) {
        logger.warn('Unauthorized mark_read attempt', { userId, matchId });
        return callback?.({ success: false, error: 'Unauthorized' });
      }

      const now = new Date();
      let query: string;
      let params: any[];

      if (messageIds && messageIds.length > 0) {
        // Mark specific messages as read
        query = `
          UPDATE messages
          SET status = 'read', read_at = $1
          WHERE match_id = $2
            AND id = ANY($3)
            AND sender_id != $4
            AND (status != 'read' OR read_at IS NULL)
          RETURNING id
        `;
        params = [now, matchId, messageIds, userId];
      } else {
        // Mark all unread messages in the match as read
        query = `
          UPDATE messages
          SET status = 'read', read_at = $1
          WHERE match_id = $2
            AND sender_id != $3
            AND (status != 'read' OR read_at IS NULL)
          RETURNING id
        `;
        params = [now, matchId, userId];
      }

      const result = await pool.query(query, params);
      const readMessageIds = result.rows.map(row => row.id);

      // Insert read receipts
      if (readMessageIds.length > 0) {
        const receiptValues = readMessageIds.map((msgId, idx) =>
          `($${idx * 3 + 1}, $${idx * 3 + 2}, $${idx * 3 + 3})`
        ).join(', ');

        const receiptParams = readMessageIds.flatMap(msgId => [msgId, userId, now]);

        await pool.query(
          `INSERT INTO read_receipts (message_id, user_id, read_at)
           VALUES ${receiptValues}
           ON CONFLICT (message_id, user_id) DO NOTHING`,
          receiptParams
        );

        // Notify sender about read receipts
        const senderId = match.user_id_1 === userId ? match.user_id_2 : match.user_id_1;
        io.to(`user:${senderId}`).emit('messages_read', {
          matchId,
          messageIds: readMessageIds,
          readBy: userId,
          readAt: now
        });

        logger.info('Messages marked as read', {
          userId,
          matchId,
          count: readMessageIds.length
        });
      }

      callback?.({ success: true, count: readMessageIds.length, messageIds: readMessageIds });
    } catch (error) {
      logger.error('Error marking messages as read', {
        error: error instanceof Error ? error.message : 'Unknown error',
        userId,
        matchId: data.matchId
      });
      callback?.({ success: false, error: 'Failed to mark messages as read' });
    }
  });

  /**
   * Handle typing indicators
   */
  socket.on('typing', async (data: TypingData, callback) => {
    try {
      const { matchId, isTyping } = data;

      // Verify user is part of the match
      const matchCheck = await pool.query(
        'SELECT user_id_1, user_id_2 FROM matches WHERE id = $1',
        [matchId]
      );

      if (matchCheck.rows.length === 0) {
        return callback?.({ success: false, error: 'Match not found' });
      }

      const match = matchCheck.rows[0];
      if (match.user_id_1 !== userId && match.user_id_2 !== userId) {
        return callback?.({ success: false, error: 'Unauthorized' });
      }

      // Update typing indicator in database
      await pool.query(
        `INSERT INTO typing_indicators (match_id, user_id, is_typing, started_at)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (match_id, user_id)
         DO UPDATE SET is_typing = $3, started_at = $4`,
        [matchId, userId, isTyping, new Date()]
      );

      // Notify the other user
      const recipientId = match.user_id_1 === userId ? match.user_id_2 : match.user_id_1;
      io.to(`user:${recipientId}`).emit('user_typing', {
        matchId,
        userId,
        isTyping
      });

      callback?.({ success: true });
    } catch (error) {
      logger.error('Error handling typing indicator', {
        error: error instanceof Error ? error.message : 'Unknown error',
        userId,
        matchId: data.matchId
      });
      callback?.({ success: false, error: 'Failed to update typing status' });
    }
  });

  /**
   * Handle getting online status of matches
   */
  socket.on('get_online_status', async (data: { userIds: string[] }, callback) => {
    try {
      const { userIds } = data;

      if (!userIds || userIds.length === 0) {
        return callback?.({ success: false, error: 'User IDs required' });
      }

      // Get online status for requested users
      const result = await pool.query(
        'SELECT user_id, is_online, last_seen_at FROM user_status WHERE user_id = ANY($1)',
        [userIds]
      );

      const statuses = result.rows.map(row => ({
        userId: row.user_id,
        isOnline: row.is_online,
        lastSeenAt: row.last_seen_at
      }));

      callback?.({ success: true, statuses });
    } catch (error) {
      logger.error('Error getting online status', {
        error: error instanceof Error ? error.message : 'Unknown error',
        userId
      });
      callback?.({ success: false, error: 'Failed to get online status' });
    }
  });
};

/**
 * Update user's online status
 */
export const updateUserStatus = async (
  pool: Pool,
  userId: string,
  isOnline: boolean,
  socketId?: string
) => {
  try {
    await pool.query(
      `INSERT INTO user_status (user_id, is_online, last_seen_at, socket_id, updated_at)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (user_id)
       DO UPDATE SET
         is_online = $2,
         last_seen_at = $3,
         socket_id = $4,
         updated_at = $5`,
      [userId, isOnline, new Date(), socketId, new Date()]
    );

    logger.debug('User status updated', { userId, isOnline, socketId });
  } catch (error) {
    logger.error('Error updating user status', {
      error: error instanceof Error ? error.message : 'Unknown error',
      userId,
      isOnline
    });
  }
};
