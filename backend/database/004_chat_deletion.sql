-- NOTE: init.sql now creates `is_deleted` directly on chat_participants, so
-- this migration is only needed for a database created before that column
-- existed. Safe to re-run (uses IF NOT EXISTS); not required for a fresh clone.
--
-- Lets a user remove a chat from their own chat list (without affecting the
-- other participant) via swipe-to-delete, powering the "delete chat" feature.
-- Mirrors is_archived: the chat reappears for that user automatically the
-- next time a new message arrives in it.
ALTER TABLE chat_participants
    ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN DEFAULT FALSE;
