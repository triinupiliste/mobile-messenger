ALTER TABLE users
    ADD COLUMN IF NOT EXISTS verification_token_expires TIMESTAMP;

-- Existing accounts predate email verification and have no verification token.
-- Grandfather them so enabling this feature does not lock current users out.
UPDATE users
SET is_verified = TRUE
WHERE verification_token IS NULL
  AND is_verified = FALSE;

CREATE INDEX IF NOT EXISTS idx_users_verification_token
    ON users (verification_token)
    WHERE verification_token IS NOT NULL;
