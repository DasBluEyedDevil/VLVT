-- Migration 005: Add Subscriptions Table for Backend Validation
-- This table stores RevenueCat subscription status synced via webhooks
-- Prevents client-side paywall bypass

CREATE TABLE IF NOT EXISTS user_subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  -- Subscription details
  is_active BOOLEAN NOT NULL DEFAULT false,
  product_id TEXT, -- e.g., 'premium_monthly', 'premium_yearly'
  purchase_date TIMESTAMP WITH TIME ZONE,
  expires_at TIMESTAMP WITH TIME ZONE, -- NULL for lifetime subscriptions

  -- RevenueCat integration
  revenuecat_subscriber_id TEXT,
  revenuecat_original_transaction_id TEXT,

  -- Metadata
  platform TEXT, -- 'ios' or 'android'
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

  UNIQUE(user_id, revenuecat_original_transaction_id)
);

-- Index for fast subscription lookups
CREATE INDEX IF NOT EXISTS idx_user_subscriptions_user_id ON user_subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_user_subscriptions_active ON user_subscriptions(user_id, is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_user_subscriptions_expires_at ON user_subscriptions(expires_at) WHERE expires_at IS NOT NULL;

-- Add swipes table if it doesn't exist (for like tracking)
CREATE TABLE IF NOT EXISTS swipes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  target_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  action TEXT NOT NULL CHECK (action IN ('like', 'pass')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

  UNIQUE(user_id, target_user_id)
);

-- Index for counting daily likes
CREATE INDEX IF NOT EXISTS idx_swipes_user_id_created_at ON swipes(user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_swipes_action ON swipes(action);

COMMENT ON TABLE user_subscriptions IS 'Stores subscription status synced from RevenueCat webhooks for backend validation';
COMMENT ON TABLE swipes IS 'Stores user swipe actions (like/pass) for analytics and daily limit enforcement';
