import pool from '../config/database';
import { Message, MessageStatus, MediaType } from '../models/message.model';
import { encryptText, decryptText } from '../utils/encryption.util';

export class MessageRepository {
    static async saveMessage(
        chatId: string, 
        senderId: string, 
        content?: string, 
        mediaUrl?: string, 
        mediaType: MediaType = 'text'
    ): Promise<Message> {
        const encryptedContent = content ? encryptText(content) : null;
        const query = `
            INSERT INTO messages (chat_id, sender_id, content, media_url, media_type, status) 
            VALUES ($1, $2, $3, $4, $5, 'sent') 
            RETURNING *`;
        const result = await pool.query(query, [chatId, senderId, encryptedContent, mediaUrl, mediaType]);
        const msg: Message = result.rows[0];
        if (msg.content) msg.content = decryptText(msg.content);
        return msg;
    }

    static async getMessagesForChat(chatId: string): Promise<Message[]> {
        const query = `
            SELECT * FROM messages 
            WHERE chat_id = $1 
            ORDER BY created_at ASC`;
        const result = await pool.query(query, [chatId]);
        
        return result.rows.map((msg: Message) => ({
            ...msg,
            content: msg.content ? decryptText(msg.content) : null
        }));
    }

    static async updateMessageStatus(messageId: string, status: MessageStatus): Promise<void> {
        const query = 'UPDATE messages SET status = $2 WHERE id = $1';
        await pool.query(query, [messageId, status]);
    }

    static async editMessage(messageId: string, senderId: string, newContent: string): Promise<Message | null> {
        const encryptedContent = encryptText(newContent);
        const query = `
            UPDATE messages 
            SET content = $3, is_edited = TRUE 
            WHERE id = $1 AND sender_id = $2 AND is_deleted = FALSE 
            RETURNING *`;
        const result = await pool.query(query, [messageId, senderId, encryptedContent]);
        const msg: Message = result.rows[0];
        if (msg && msg.content) msg.content = decryptText(msg.content);
        return msg || null;
    }

    static async deleteMessage(messageId: string, senderId: string): Promise<boolean> {
        const query = `
            UPDATE messages 
            SET is_deleted = TRUE, content = NULL, media_url = NULL 
            WHERE id = $1 AND sender_id = $2`;
        const result = await pool.query(query, [messageId, senderId]);
        return (result.rowCount ?? 0) > 0;
    }
}