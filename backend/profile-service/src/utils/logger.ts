/**
 * Profile Service Logger
 * Creates a logger instance configured for profile-service
 */

import { createLogger } from '@vlvt/shared';

const logger = createLogger({
  service: 'profile-service',
});

export default logger;
