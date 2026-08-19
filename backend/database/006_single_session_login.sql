-- NOTE: init.sql now creates `session_version` directly on users, so this
-- migration is only needed for a database created before that column
-- existed. Safe to re-run (uses IF NOT EXISTS); not required for a fresh
-- clone. Also auto-applied on every server startup via
-- ensureSessionVersionColumn() in migrate.ts, so running this file by hand
-- is not required either — it's kept here purely for schema history.
--
-- Backs single-active-session enforcement: bumped on every login, and
-- embedded in the freshly-issued JWT. Any older token (e.g. held by a
-- different device that's already logged in) carries a stale version and
-- gets rejected by the auth middleware/socket handshake, so logging in on a
-- new device signs the account out everywhere else.
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS session_version INTEGER NOT NULL DEFAULT 0;
