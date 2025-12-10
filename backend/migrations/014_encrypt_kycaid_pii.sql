-- Migration: Encrypt KYCAID PII data
-- Description: Encrypt sensitive government ID data to comply with GDPR/privacy requirements
-- Date: 2025-12-09
-- CRITICAL: This migration requires KYCAID_ENCRYPTION_KEY environment variable to be set

-- ============================================
-- 1. ENABLE PGCRYPTO EXTENSION
-- ============================================
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================
-- 2. ADD ENCRYPTED COLUMNS
-- ============================================
-- Store encrypted PII as BYTEA (binary data)
-- The encryption key should come from environment variable

ALTER TABLE kycaid_verifications
    ADD COLUMN IF NOT EXISTS encrypted_pii BYTEA;

-- ============================================
-- 3. CREATE ENCRYPTION/DECRYPTION FUNCTIONS
-- ============================================
-- Note: These functions should be called from application code
-- with the encryption key passed from environment variables.
-- DO NOT hardcode encryption keys in the database!

-- Function to encrypt PII JSON data
CREATE OR REPLACE FUNCTION encrypt_kycaid_pii(
    pii_data JSONB,
    encryption_key TEXT
) RETURNS BYTEA AS $$
BEGIN
    -- AES-256 encryption in CBC mode with PKCS padding
    RETURN pgp_sym_encrypt(
        pii_data::TEXT,
        encryption_key,
        'cipher-algo=aes256, compress-algo=1'
    );
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Function to decrypt PII JSON data
CREATE OR REPLACE FUNCTION decrypt_kycaid_pii(
    encrypted_data BYTEA,
    encryption_key TEXT
) RETURNS JSONB AS $$
BEGIN
    RETURN pgp_sym_decrypt(
        encrypted_data,
        encryption_key
    )::JSONB;
EXCEPTION
    WHEN OTHERS THEN
        -- Return NULL if decryption fails (wrong key, corrupted data)
        RETURN NULL;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================
-- 4. ADD COMMENTS DOCUMENTING THE SECURITY
-- ============================================
COMMENT ON COLUMN kycaid_verifications.encrypted_pii IS
    'AES-256 encrypted JSON containing: first_name, last_name, date_of_birth, document_number, document_expiry. Key from KYCAID_ENCRYPTION_KEY env var.';

COMMENT ON FUNCTION encrypt_kycaid_pii IS
    'Encrypts KYCAID PII data using AES-256. NEVER call with hardcoded keys - use environment variable.';

COMMENT ON FUNCTION decrypt_kycaid_pii IS
    'Decrypts KYCAID PII data. Returns NULL on decryption failure. NEVER call with hardcoded keys.';

-- ============================================
-- 5. MARK PLAINTEXT COLUMNS FOR DEPRECATION
-- ============================================
-- We keep the original columns temporarily for migration
-- but mark them for removal in the next release

COMMENT ON COLUMN kycaid_verifications.first_name IS
    'DEPRECATED - Use encrypted_pii. Will be removed in future migration.';
COMMENT ON COLUMN kycaid_verifications.last_name IS
    'DEPRECATED - Use encrypted_pii. Will be removed in future migration.';
COMMENT ON COLUMN kycaid_verifications.date_of_birth IS
    'DEPRECATED - Use encrypted_pii. Will be removed in future migration.';
COMMENT ON COLUMN kycaid_verifications.document_number IS
    'DEPRECATED - Use encrypted_pii. Will be removed in future migration.';
COMMENT ON COLUMN kycaid_verifications.document_expiry IS
    'DEPRECATED - Use encrypted_pii. Will be removed in future migration.';

-- Note: The actual data migration from plaintext to encrypted
-- must be done via application code that has access to the encryption key.
-- See backend/auth-service/scripts/migrate-kycaid-encryption.ts

-- ============================================
-- 6. APPLICATION CODE REQUIREMENTS
-- ============================================
-- After running this migration:
-- 1. Set KYCAID_ENCRYPTION_KEY environment variable (32-byte random key)
-- 2. Run the data migration script to encrypt existing plaintext data
-- 3. Update KYCAID callback handler to store encrypted data
-- 4. Once confirmed working, run migration to DROP plaintext columns
