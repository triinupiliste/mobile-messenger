-- Stores the device's Firebase Cloud Messaging token so the backend can send
-- push notifications (new messages, new invites) to this user's device.
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS fcm_token TEXT;
