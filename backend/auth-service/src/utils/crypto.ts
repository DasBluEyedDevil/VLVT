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
 * Generate a refresh token with 7-day expiry
 * Returns both the raw token (to send to client) and the hash (to store in database)
 */
export function generateRefreshToken(): { token: string; tokenHash: string; expires: Date } {
  const token = generateToken(64); // 128-char hex string for extra security
  const tokenHash = hashToken(token);
  return {
    token,
    tokenHash,
    expires: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000), // 7 days
  };
}

/**
 * Hash a token using SHA-256 for secure storage
 * Never store raw refresh tokens in the database
 */
export function hashToken(token: string): string {
  return crypto.createHash('sha256').update(token).digest('hex');
}

/**
 * Check if a token has expired
 */
export function isTokenExpired(expires: Date): boolean {
  return new Date() > new Date(expires);
}
