-- Migration: Add date proposals table for "Propose a Date" feature
-- Description: Enables users to propose dates with locations and times
-- Date: 2025-12-06

-- Date proposals
CREATE TABLE IF NOT EXISTS date_proposals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id VARCHAR(255) NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
  proposer_id VARCHAR(255) NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  -- Location (from Google Places)
  place_id VARCHAR(255),                 -- Google Place ID for future lookups
  place_name VARCHAR(255) NOT NULL,
  place_address VARCHAR(500),
  place_lat DECIMAL(10, 8),
  place_lng DECIMAL(11, 8),

  -- Timing
  proposed_date DATE NOT NULL,
  proposed_time TIME NOT NULL,

  -- Optional note from proposer
  note TEXT,

  -- Status tracking
  status VARCHAR(20) DEFAULT 'pending', -- pending, accepted, declined, completed, cancelled
  responded_at TIMESTAMP WITH TIME ZONE,
  completed_at TIMESTAMP WITH TIME ZONE,
  proposer_confirmed BOOLEAN DEFAULT FALSE,
  recipient_confirmed BOOLEAN DEFAULT FALSE,

  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_date_proposals_match ON date_proposals(match_id);
CREATE INDEX IF NOT EXISTS idx_date_proposals_proposer ON date_proposals(proposer_id);
CREATE INDEX IF NOT EXISTS idx_date_proposals_status ON date_proposals(status);
CREATE INDEX IF NOT EXISTS idx_date_proposals_date ON date_proposals(proposed_date);

-- Comments
COMMENT ON TABLE date_proposals IS 'Date proposals between matched users';
COMMENT ON COLUMN date_proposals.place_id IS 'Google Places API place ID for venue lookup';
COMMENT ON COLUMN date_proposals.status IS 'Status: pending, accepted, declined, completed, cancelled';
COMMENT ON COLUMN date_proposals.proposer_confirmed IS 'Whether proposer confirmed the date happened';
COMMENT ON COLUMN date_proposals.recipient_confirmed IS 'Whether recipient confirmed the date happened';
