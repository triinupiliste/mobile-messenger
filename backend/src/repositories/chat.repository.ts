import pool from '../config/database';
import { ChatListItem } from '../models/chat.model';
import { decryptFields } from '../utils/encryption.util';

export class ChatRepository {
    static async createChatBetweenUsers(user1Id: string, user2Id: string): Promise<string> {
        const client = await pool.connect();
        try {
            await client.query('BEGIN');
            const chatResult = await client.query('INSERT INTO chats DEFAULT VALUES RETURNING id');
            const chatId = chatResult.rows[0].id;

            await client.query(
                'INSERT INTO chat_participants (chat_id, user_id) VALUES ($1, $2), ($1, $3)',
                [chatId, user1Id, user2Id]
            );

            await client.query('COMMIT');
            return chatId;
        } catch (error) {
            await client.query('ROLLBACK');
            throw error;
        } finally {
            client.release();
        }
    }

    // Looks for a chat that already exists between these users (e.g. from
    // before they unfriended) so re-accepting an invite revives it instead of creating a new one.
    static async findChatBetweenUsers(user1Id: string, user2Id: string): Promise<string | null> {
        const query = `
            SELECT cp1.chat_id FROM chat_participants cp1
            JOIN chat_participants cp2 ON cp1.chat_id = cp2.chat_id
            WHERE cp1.user_id = $1 AND cp2.user_id = $2
            LIMIT 1`;
        const result = await pool.query(query, [user1Id, user2Id]);
        return result.rows[0]?.chat_id || null;
    }

    // Distinct "other participant" ids across all this user's chats — used to
    // know who to notify live on profile/avatar changes.
    static async getContactIds(userId: string): Promise<string[]> {
        const query = `
            SELECT DISTINCT other_cp.user_id AS contact_id
            FROM chat_participants cp
            JOIN chat_participants other_cp ON cp.chat_id = other_cp.chat_id AND other_cp.user_id != $1
            WHERE cp.user_id = $1`;
        const result = await pool.query(query, [userId]);
        return result.rows.map((row: any) => row.contact_id);
    }

    static async getChatListForUser(userId: string): Promise<ChatListItem[]> {
        const query = `
            SELECT 
                cp.chat_id,
                cp.is_archived,
                cp.is_muted,
                other_cp.user_id AS contact_id,
                u.username AS contact_username,
                p.avatar_url AS contact_avatar,
                m.content AS last_message_content,
                m.media_type AS last_message_type,
                m.status AS last_message_status,
                m.sender_id AS last_message_sender_id,
                m.created_at AS last_message_time,
                COALESCE(unread.unread_count, 0)::int AS unread_count
            FROM chat_participants cp
            JOIN chat_participants other_cp ON cp.chat_id = other_cp.chat_id AND other_cp.user_id != $1
            JOIN users u ON other_cp.user_id = u.id
            LEFT JOIN profiles p ON u.id = p.user_id
            LEFT JOIN LATERAL (
                SELECT content, media_type, status, sender_id, created_at 
                FROM messages 
                WHERE chat_id = cp.chat_id AND is_deleted = FALSE 
                ORDER BY created_at DESC 
                LIMIT 1
            ) m ON true
            LEFT JOIN LATERAL (
                SELECT COUNT(*) AS unread_count
                FROM messages msg2
                WHERE msg2.chat_id = cp.chat_id
                  AND msg2.sender_id != $1
                  AND msg2.status != 'read'
                  AND msg2.is_deleted = FALSE
            ) unread ON true
            WHERE cp.user_id = $1 AND cp.is_deleted = FALSE
            ORDER BY m.created_at DESC NULLS LAST`;

        const result = await pool.query(query, [userId]);
        
        // Decrypt text previews and avatar URLs for the chat list
        return result.rows.map((row: any) => decryptFields(row, ['contact_avatar', 'last_message_content']));
    }

    static async setChatArchivedStatus(chatId: string, userId: string, isArchived: boolean): Promise<void> {
        const query = `
            UPDATE chat_participants 
            SET is_archived = $3 
            WHERE chat_id = $1 AND user_id = $2`;
        await pool.query(query, [chatId, userId, isArchived]);
    }

    static async setChatMutedStatus(chatId: string, userId: string, isMuted: boolean): Promise<void> {
        const query = `
            UPDATE chat_participants 
            SET is_muted = $3 
            WHERE chat_id = $1 AND user_id = $2`;
        await pool.query(query, [chatId, userId, isMuted]);
    }

    static async setChatDeletedStatus(chatId: string, userId: string, isDeleted: boolean): Promise<void> {
        // Deleting also stamps `cleared_at`, resetting the deleter's history so
        // they only see messages sent after this point (per-device delete, like WhatsApp).
        const query = isDeleted
            ? `UPDATE chat_participants 
               SET is_deleted = TRUE, cleared_at = NOW() 
               WHERE chat_id = $1 AND user_id = $2`
            : `UPDATE chat_participants 
               SET is_deleted = FALSE 
               WHERE chat_id = $1 AND user_id = $2`;
        await pool.query(query, [chatId, userId]);
    }

    // Un-hides a chat for anyone who'd archived/deleted/unfriended it — used on
    // new messages and when a re-accepted invite revives an old chat.
    static async reviveForAllParticipants(chatId: string): Promise<void> {
        const query = `
            UPDATE chat_participants 
            SET is_archived = FALSE, is_deleted = FALSE 
            WHERE chat_id = $1 AND (is_archived = TRUE OR is_deleted = TRUE)`;
        await pool.query(query, [chatId]);
    }

    // Hides the shared chat for both participants, but (unlike a manual delete)
    // leaves `cleared_at` untouched so history reappears if they reconnect.
    static async removeFriendship(chatId: string): Promise<void> {
        const query = `
            UPDATE chat_participants 
            SET is_deleted = TRUE, is_archived = FALSE 
            WHERE chat_id = $1`;
        await pool.query(query, [chatId]);
    }

    // Every other participant in the chat, plus their mute state and FCM token
    // — used to decide who to push a "new message" notification to.
    static async getOtherParticipantsForPush(
        chatId: string,
        excludeUserId: string,
    ): Promise<{ user_id: string; is_muted: boolean; fcm_token: string | null }[]> {
        const query = `
            SELECT cp.user_id, cp.is_muted, u.fcm_token
            FROM chat_participants cp
            JOIN users u ON u.id = cp.user_id
            WHERE cp.chat_id = $1 AND cp.user_id != $2`;
        const result = await pool.query(query, [chatId, excludeUserId]);
        return result.rows;
    }
}