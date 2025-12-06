-- Migration 007: Add Refresh Tokens Table for Secure Token Management
-- This migration creates a table for refresh tokens to support short-lived access tokens
-- Access tokens expire in 15 minutes, refresh tokens expire in 7 days and can be revoked

-- Refresh tokens table
CREATE TABLE IF NOT EXISTS refresh_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id VARCHAR(255) NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  -- Token information
  token_hash VARCHAR(64) NOT NULL UNIQUE, -- SHA-256 hash of the refresh token

  -- Token metadata
  device_info VARCHAR(500), -- Optional device/browser info for audit
  ip_address VARCHAR(45), -- IPv4 or IPv6 address

  -- Token lifecycle
  expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  last_used_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  revoked_at TIMESTAMP WITH TIME ZONE, -- NULL if not revoked

  -- Revocation tracking
  revoked_reason VARCHAR(100) -- 'logout', 'password_change', 'security_concern', 'admin_action'
);

-- Indexes for fast lookups
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user_id ON refresh_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_token_hash ON refresh_tokens(token_hash);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_expires_at ON refresh_tokens(expires_at);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_active ON refresh_tokens(user_id, revoked_at)
  WHERE revoked_at IS NULL;

-- Table comment
COMMENT ON TABLE refresh_tokens IS 'Stores refresh tokens for secure token rotation. Refresh tokens are hashed for security. Supports revocation for logout and security events.';

-- Column comments
COMMENT ON COLUMN refresh_tokens.token_hash IS 'SHA-256 hash of the refresh token (never store raw token)';
COMMENT ON COLUMN refresh_tokens.device_info IS 'User agent or device identifier for audit purposes';
COMMENT ON COLUMN refresh_tokens.ip_address IS 'IP address from which the token was issued';
COMMENT ON COLUMN refresh_tokens.expires_at IS 'Token expiration timestamp (typically 7 days from creation)';
COMMENT ON COLUMN refresh_tokens.revoked_at IS 'Timestamp when token was revoked (NULL if active)';
COMMENT ON COLUMN refresh_tokens.revoked_reason IS 'Reason for revocation: logout, password_change, security_concern, admin_action';

-- Function to clean up expired refresh tokens (run periodically via cron or pg_cron)
CREATE OR REPLACE FUNCTION cleanup_expired_refresh_tokens()
RETURNS INTEGER AS $$
DECLARE
  deleted_count INTEGER;
BEGIN
  DELETE FROM refresh_tokens
  WHERE expires_at < NOW() - INTERVAL '1 day'
     OR (revoked_at IS NOT NULL AND revoked_at < NOW() - INTERVAL '30 days');

  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION cleanup_expired_refresh_tokens() IS 'Removes expired tokens (1 day past expiry) and old revoked tokens (30 days past revocation)';
