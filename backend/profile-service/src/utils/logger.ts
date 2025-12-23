/**
 * Profile Service Logger
 * Creates a logger instance configured for profile-service
 */

import { createLogger } from '../shared';

const logger = createLogger({
  service: 'profile-service',
});

export default logger;
