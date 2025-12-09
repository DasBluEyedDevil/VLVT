-- Migration: Fix data integrity issues
-- Description: Fix typing_indicators match_id type and add FK constraints to safety tables
-- Date: 2025-12-09

-- ============================================
-- 1. FIX typing_indicators.match_id TYPE
-- ============================================
-- matches.id is VARCHAR(255) but typing_indicators.match_id was INTEGER
-- This causes foreign key constraint issues

-- Drop the old table and recreate with correct type
DROP TABLE IF EXISTS typing_indicators;

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

COMMENT ON TABLE typing_indicators IS 'Tracks real-time typing indicators in conversations';

-- ============================================
-- 2. ADD FK CONSTRAINTS TO SAFETY TABLES
-- ============================================
-- blocks and reports tables are missing foreign key constraints

-- Add FK constraints to blocks table
-- First check if constraint exists, then add if not
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'fk_blocks_user_id'
        AND table_name = 'blocks'
    ) THEN
        ALTER TABLE blocks
            ADD CONSTRAINT fk_blocks_user_id
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'fk_blocks_blocked_user_id'
        AND table_name = 'blocks'
    ) THEN
        ALTER TABLE blocks
            ADD CONSTRAINT fk_blocks_blocked_user_id
            FOREIGN KEY (blocked_user_id) REFERENCES users(id) ON DELETE CASCADE;
    END IF;
END $$;

-- Add FK constraints to reports table
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'fk_reports_reporter_id'
        AND table_name = 'reports'
    ) THEN
        ALTER TABLE reports
            ADD CONSTRAINT fk_reports_reporter_id
            FOREIGN KEY (reporter_id) REFERENCES users(id) ON DELETE CASCADE;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'fk_reports_reported_user_id'
        AND table_name = 'reports'
    ) THEN
        ALTER TABLE reports
            ADD CONSTRAINT fk_reports_reported_user_id
            FOREIGN KEY (reported_user_id) REFERENCES users(id) ON DELETE CASCADE;
    END IF;
END $$;

-- Add comments
COMMENT ON CONSTRAINT fk_blocks_user_id ON blocks IS 'User who created the block';
COMMENT ON CONSTRAINT fk_blocks_blocked_user_id ON blocks IS 'User who was blocked';
COMMENT ON CONSTRAINT fk_reports_reporter_id ON reports IS 'User who submitted the report';
COMMENT ON CONSTRAINT fk_reports_reported_user_id ON reports IS 'User who was reported';
