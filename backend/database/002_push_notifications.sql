-- NOTE: init.sql now creates `fcm_token` directly, so this migration is only
-- needed for a database created before that column existed. Safe to re-run
-- (uses IF NOT EXISTS); not required for a fresh clone.
--
-- Stores the device's Firebase Cloud Messaging token so the backend can send
-- push notifications (new messages, new invites) to this user's device.
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS fcm_token TEXT;
