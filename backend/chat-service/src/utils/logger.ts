/**
 * Chat Service Logger
 * Creates a logger instance configured for chat-service
 */

import { createLogger } from '@vlvt/shared';

const logger = createLogger({
  service: 'chat-service',
});

export default logger;
