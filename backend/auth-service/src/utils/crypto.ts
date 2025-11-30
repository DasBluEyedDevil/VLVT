import crypto from 'crypto';

/**
 * Generate a cryptographically secure random token
 * @param bytes Number of random bytes (default 32, produces 64-char hex string)
 */
export function generateToken(bytes: number = 32): string {
  return crypto.randomBytes(bytes).toString('hex');
}

/**
 * Generate a verification token with 24-hour expiry
 */
export function generateVerificationToken(): { token: string; expires: Date } {
  return {
    token: generateToken(32),
    expires: new Date(Date.now() + 24 * 60 * 60 * 1000), // 24 hours
  };
}

/**
 * Generate a password reset token with 1-hour expiry
 */
export function generateResetToken(): { token: string; expires: Date } {
  return {
    token: generateToken(32),
    expires: new Date(Date.now() + 60 * 60 * 1000), // 1 hour
  };
}

/**
 * Check if a token has expired
 */
export function isTokenExpired(expires: Date): boolean {
  return new Date() > new Date(expires);
}
