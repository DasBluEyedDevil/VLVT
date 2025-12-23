/**
 * Environment Variable Validator
 * Ensures required environment variables are present before service startup
 */

export interface EnvConfig {
  /** Required environment variables - service will exit if any are missing */
  required: string[];
  /** Optional environment variables with default values */
  optional?: Record<string, string>;
  /** Validate format of specific variables */
  validate?: Record<string, (value: string) => boolean>;
}

export interface ValidationResult {
  valid: boolean;
  missing: string[];
  invalid: string[];
  warnings: string[];
}

/**
 * Validate environment variables for a service
 * @param config - Environment configuration
 * @param serviceName - Name of the service for logging
 * @param exitOnError - Exit process if validation fails (default: true)
 * @returns Validation result
 */
export const validateEnv = (
  config: EnvConfig,
  serviceName: string,
  exitOnError = true
): ValidationResult => {
  const result: ValidationResult = {
    valid: true,
    missing: [],
    invalid: [],
    warnings: [],
  };

  // Check required variables
  for (const key of config.required) {
    if (!process.env[key]) {
      result.missing.push(key);
      result.valid = false;
    }
  }

  // Set defaults for optional variables
  if (config.optional) {
    for (const [key, defaultValue] of Object.entries(config.optional)) {
      if (!process.env[key]) {
        process.env[key] = defaultValue;
        result.warnings.push(`Using default for ${key}: ${defaultValue}`);
      }
    }
  }

  // Validate format of specific variables
  if (config.validate) {
    for (const [key, validator] of Object.entries(config.validate)) {
      const value = process.env[key];
      if (value && !validator(value)) {
        result.invalid.push(key);
        result.valid = false;
      }
    }
  }

  // Log and potentially exit
  if (!result.valid) {
    console.error(`\n[${serviceName}] Environment validation failed:\n`);

    if (result.missing.length > 0) {
      console.error('Missing required variables:');
      result.missing.forEach(key => console.error(`  - ${key}`));
    }

    if (result.invalid.length > 0) {
      console.error('\nInvalid variable format:');
      result.invalid.forEach(key => console.error(`  - ${key}`));
    }

    console.error('\nPlease set these environment variables and restart.\n');

    if (exitOnError && process.env.NODE_ENV !== 'test') {
      process.exit(1);
    }
  } else {
    // Log warnings
    if (result.warnings.length > 0 && process.env.NODE_ENV !== 'test') {
      console.log(`[${serviceName}] Environment warnings:`);
      result.warnings.forEach(warning => console.log(`  - ${warning}`));
    }
  }

  return result;
};

/**
 * Common validators for environment variables
 */
export const validators = {
  /** Validate URL format */
  isUrl: (value: string): boolean => {
    try {
      new URL(value);
      return true;
    } catch {
      return false;
    }
  },

  /** Validate port number */
  isPort: (value: string): boolean => {
    const port = parseInt(value, 10);
    return !isNaN(port) && port > 0 && port <= 65535;
  },

  /** Validate boolean string */
  isBoolean: (value: string): boolean => {
    return ['true', 'false', '1', '0'].includes(value.toLowerCase());
  },

  /** Validate positive integer */
  isPositiveInt: (value: string): boolean => {
    const num = parseInt(value, 10);
    return !isNaN(num) && num > 0;
  },

  /** Validate email format */
  isEmail: (value: string): boolean => {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailRegex.test(value);
  },

  /** Validate non-empty string */
  isNonEmpty: (value: string): boolean => {
    return value.trim().length > 0;
  },
};

/**
 * Pre-configured environment configs for each service
 */
export const serviceEnvConfigs = {
  auth: {
    required: ['DATABASE_URL', 'JWT_SECRET'],
    optional: {
      PORT: '3001',
      NODE_ENV: 'development',
      CORS_ORIGIN: 'http://localhost:19006',
      LOG_LEVEL: 'info',
    },
  } as EnvConfig,

  profile: {
    required: ['DATABASE_URL', 'JWT_SECRET'],
    optional: {
      PORT: '3002',
      NODE_ENV: 'development',
      CORS_ORIGIN: 'http://localhost:19006',
      LOG_LEVEL: 'info',
    },
  } as EnvConfig,

  chat: {
    required: ['DATABASE_URL', 'JWT_SECRET'],
    optional: {
      PORT: '3003',
      NODE_ENV: 'development',
      CORS_ORIGIN: 'http://localhost:19006',
      LOG_LEVEL: 'info',
    },
  } as EnvConfig,
};
