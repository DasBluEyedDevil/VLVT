-- Migration 004: Add Real-time Features Support
-- This migration adds support for:
-- 1. Message status tracking (delivered, read)
-- 2. Read receipts
-- 3. Location services (geolocation)
-- 4. Firebase Cloud Messaging tokens

-- ============================================
-- 1. MESSAGE STATUS TRACKING
-- ============================================

-- Add status tracking columns to messages table
ALTER TABLE messages
ADD COLUMN IF NOT EXISTS status VARCHAR(20) DEFAULT 'sent',
ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS read_at TIMESTAMP WITH TIME ZONE;

-- Create index for efficient status queries
CREATE INDEX IF NOT EXISTS idx_messages_status ON messages(status);
CREATE INDEX IF NOT EXISTS idx_messages_delivered_at ON messages(delivered_at);
CREATE INDEX IF NOT EXISTS idx_messages_read_at ON messages(read_at);

-- ============================================
-- 2. READ RECEIPTS
-- ============================================

-- Create read_receipts table for tracking who read what message
CREATE TABLE IF NOT EXISTS read_receipts (
    message_id VARCHAR(255) NOT NULL,
    user_id VARCHAR(255) NOT NULL,
    read_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (message_id, user_id),
    CONSTRAINT fk_read_receipt_message FOREIGN KEY (message_id)
        REFERENCES messages(id) ON DELETE CASCADE,
    CONSTRAINT fk_read_receipt_user FOREIGN KEY (user_id)
        REFERENCES users(id) ON DELETE CASCADE
);

-- Create index for efficient lookups
CREATE INDEX IF NOT EXISTS idx_read_receipts_user ON read_receipts(user_id);
CREATE INDEX IF NOT EXISTS idx_read_receipts_message ON read_receipts(message_id);

-- ============================================
-- 3. LOCATION SERVICES
-- ============================================

-- Add geolocation columns to profiles table
ALTER TABLE profiles
ADD COLUMN IF NOT EXISTS latitude DECIMAL(10, 8),
ADD COLUMN IF NOT EXISTS longitude DECIMAL(11, 8),
ADD COLUMN IF NOT EXISTS location_updated_at TIMESTAMP WITH TIME ZONE;

-- Create spatial index for efficient distance queries
-- Note: Using standard B-tree index. For production, consider PostGIS extension
CREATE INDEX IF NOT EXISTS idx_profiles_latitude ON profiles(latitude);
CREATE INDEX IF NOT EXISTS idx_profiles_longitude ON profiles(longitude);
CREATE INDEX IF NOT EXISTS idx_profiles_location ON profiles(latitude, longitude);

-- Add check constraints to ensure valid coordinates (idempotent)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'check_latitude'
    ) THEN
        ALTER TABLE profiles
        ADD CONSTRAINT check_latitude
            CHECK (latitude IS NULL OR (latitude >= -90 AND latitude <= 90));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'check_longitude'
    ) THEN
        ALTER TABLE profiles
        ADD CONSTRAINT check_longitude
            CHECK (longitude IS NULL OR (longitude >= -180 AND longitude <= 180));
    END IF;
END $$;

-- ============================================
-- 4. FIREBASE CLOUD MESSAGING TOKENS
-- ============================================

-- Create fcm_tokens table for push notifications
CREATE TABLE IF NOT EXISTS fcm_tokens (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(255) NOT NULL,
    token TEXT NOT NULL,
    device_type VARCHAR(20) CHECK (device_type IN ('ios', 'android', 'web')),
    device_id VARCHAR(255), -- Optional device identifier
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_used_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_fcm_token_user FOREIGN KEY (user_id)
        REFERENCES users(id) ON DELETE CASCADE,
    UNIQUE(user_id, token)
);

-- Create indexes for efficient lookups
CREATE INDEX IF NOT EXISTS idx_fcm_tokens_user ON fcm_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_fcm_tokens_active ON fcm_tokens(is_active);

-- ============================================
-- 5. ONLINE STATUS TRACKING (BONUS)
-- ============================================

-- Create user_status table for tracking online/offline status
CREATE TABLE IF NOT EXISTS user_status (
    user_id VARCHAR(255) PRIMARY KEY,
    is_online BOOLEAN DEFAULT false,
    last_seen_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    socket_id VARCHAR(255), -- Current Socket.IO connection ID
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_user_status_user FOREIGN KEY (user_id)
        REFERENCES users(id) ON DELETE CASCADE
);

-- Create index for online status queries
CREATE INDEX IF NOT EXISTS idx_user_status_online ON user_status(is_online);
CREATE INDEX IF NOT EXISTS idx_user_status_last_seen ON user_status(last_seen_at);

-- ============================================
-- 6. TYPING INDICATORS (BONUS)
-- ============================================

-- Create typing_indicators table for real-time typing status
-- Note: match_id is VARCHAR(255) to match matches.id type
CREATE TABLE IF NOT EXISTS typing_indicators (
    match_id VARCHAR(255) NOT NULL,
    user_id VARCHAR(255) NOT NULL,
    is_typing BOOLEAN DEFAULT false,
    started_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (match_id, user_id),
    CONSTRAINT fk_typing_match FOREIGN KEY (match_id)
        REFERENCES matches(id) ON DELETE CASCADE,
    CONSTRAINT fk_typing_user FOREIGN KEY (user_id)
        REFERENCES users(id) ON DELETE CASCADE
);

-- ============================================
-- COMMENTS AND DOCUMENTATION
-- ============================================

COMMENT ON TABLE read_receipts IS 'Tracks when users read specific messages';
COMMENT ON TABLE fcm_tokens IS 'Stores Firebase Cloud Messaging tokens for push notifications';
COMMENT ON TABLE user_status IS 'Tracks online/offline status and last seen timestamp';
COMMENT ON TABLE typing_indicators IS 'Tracks real-time typing indicators in conversations';

COMMENT ON COLUMN messages.status IS 'Message delivery status: sent, delivered, read, failed';
COMMENT ON COLUMN messages.delivered_at IS 'Timestamp when message was delivered to recipient';
COMMENT ON COLUMN messages.read_at IS 'Timestamp when message was read by recipient';

COMMENT ON COLUMN profiles.latitude IS 'User latitude coordinate (WGS84)';
COMMENT ON COLUMN profiles.longitude IS 'User longitude coordinate (WGS84)';
COMMENT ON COLUMN profiles.location_updated_at IS 'Last time location was updated';

COMMENT ON COLUMN fcm_tokens.is_active IS 'Whether this FCM token is still valid and active';
COMMENT ON COLUMN fcm_tokens.device_type IS 'Type of device: ios, android, or web';
