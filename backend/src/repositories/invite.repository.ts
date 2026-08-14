import pool from '../config/database';
import { Invite, InviteStatus } from '../models/invite.model';
import { decryptText } from '../utils/encryption.util';

export class InviteRepository {
    static async createInvite(senderId: string, receiverId: string): Promise<Invite> {
        const query = `
            INSERT INTO invites (sender_id, receiver_id, status) 
            VALUES ($1, $2, 'pending') 
            RETURNING *`;
        const result = await pool.query(query, [senderId, receiverId]);
        return result.rows[0];
    }

    static async findExistingInvite(senderId: string, receiverId: string): Promise<Invite | null> {
        const query = `
            SELECT * FROM invites 
            WHERE ((sender_id = $1 AND receiver_id = $2) 
                OR (sender_id = $2 AND receiver_id = $1))
              AND status IN ('pending', 'accepted')`;
        const result = await pool.query(query, [senderId, receiverId]);
        return result.rows[0] || null;
    }

    static async getPendingInvitesForUser(userId: string) {
        const query = `
            SELECT i.id, i.sender_id, i.status, i.created_at,
                   json_build_object(
                       'id', u.id,
                       'username', u.username,
                       'email', u.email,
                       'avatar_url', p.avatar_url
                   ) AS sender
            FROM invites i
            JOIN users u ON i.sender_id = u.id
            LEFT JOIN profiles p ON u.id = p.user_id
            WHERE i.receiver_id = $1 AND i.status = 'pending'
            ORDER BY i.created_at DESC`;
        const result = await pool.query(query, [userId]);
        return result.rows.map((row: any) => ({
            ...row,
            sender: {
                ...row.sender,
                avatar_url: row.sender?.avatar_url ? decryptText(row.sender.avatar_url) : row.sender?.avatar_url,
            },
        }));
    }

    static async getOutgoingInvitesForUser(userId: string) {
        const query = `
            SELECT i.id, i.receiver_id, i.status, i.created_at,
                   json_build_object(
                       'id', u.id,
                       'username', u.username,
                       'email', u.email,
                       'avatar_url', p.avatar_url
                   ) AS recipient
            FROM invites i
            JOIN users u ON i.receiver_id = u.id
            LEFT JOIN profiles p ON u.id = p.user_id
            WHERE i.sender_id = $1 AND i.status = 'pending'
            ORDER BY i.created_at DESC`;
        const result = await pool.query(query, [userId]);
        return result.rows.map((row: any) => ({
            ...row,
            recipient: {
                ...row.recipient,
                avatar_url: row.recipient?.avatar_url ? decryptText(row.recipient.avatar_url) : row.recipient?.avatar_url,
            },
        }));
    }

    static async updateInviteStatus(inviteId: string, status: InviteStatus): Promise<Invite | null> {
        const query = `
            UPDATE invites SET status = $2 
            WHERE id = $1 
            RETURNING *`;
        const result = await pool.query(query, [inviteId, status]);
        return result.rows[0] || null;
    }

    static async findById(inviteId: string): Promise<Invite | null> {
        const query = 'SELECT * FROM invites WHERE id = $1';
        const result = await pool.query(query, [inviteId]);
        return result.rows[0] || null;
    }
}