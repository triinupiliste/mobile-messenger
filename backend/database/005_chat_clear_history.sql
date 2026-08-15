-- NOTE: init.sql now creates `cleared_at` directly on chat_participants, so
-- this migration is only needed for a database created before that column
-- existed. Safe to re-run (uses IF NOT EXISTS); not required for a fresh clone.
--
-- Marks the point in time a user "deleted" a chat from their own list.
-- Messages sent before this timestamp are hidden only for that user (like
-- WhatsApp/Messenger's "delete chat" — the other participant's view, and the
-- messages themselves, are unaffected).
ALTER TABLE chat_participants
    ADD COLUMN IF NOT EXISTS cleared_at TIMESTAMP;
