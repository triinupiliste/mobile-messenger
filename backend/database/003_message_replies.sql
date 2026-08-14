-- NOTE: init.sql now creates `reply_to_id` directly, so this migration is
-- only needed for a database created before that column existed. Safe to
-- re-run (uses IF NOT EXISTS); not required for a fresh clone.
--
-- Lets a message reference another message in the same chat as the one it is
-- replying to, powering the swipe-to-reply feature.
ALTER TABLE messages
    ADD COLUMN IF NOT EXISTS reply_to_id UUID REFERENCES messages(id) ON DELETE SET NULL;
