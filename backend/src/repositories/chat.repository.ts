import pool from '../config/database';
import { ChatListItem } from '../models/chat.model';
import { decryptText } from '../utils/encryption.util';

export class ChatRepository {
    static async createChatBetweenUsers(user1Id: string, user2Id: string): Promise<string> {
        const client = await pool.connect();
        try {
            await client.query('BEGIN');
            // Create chat entity
            const chatResult = await client.query('INSERT INTO chats DEFAULT VALUES RETURNING id');
            const chatId = chatResult.rows[0].id;

            // Link participants
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
            WHERE cp.user_id = $1
            ORDER BY m.created_at DESC NULLS LAST`;

        const result = await pool.query(query, [userId]);
        
        // Decrypt text previews for the chat list
        return result.rows.map((row: any) => ({
            ...row,
            last_message_content: row.last_message_content ? decryptText(row.last_message_content) : null
        }));
    }

    static async setChatArchivedStatus(chatId: string, userId: string, isArchived: boolean): Promise<void> {
        const query = `
            UPDATE chat_participants 
            SET is_archived = $3 
            WHERE chat_id = $1 AND user_id = $2`;
        await pool.query(query, [chatId, userId, isArchived]);
    }
}