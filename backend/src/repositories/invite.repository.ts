import pool from '../config/database';
import { Invite, InviteStatus } from '../models/invite.model';

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
            WHERE (sender_id = $1 AND receiver_id = $2) 
               OR (sender_id = $2 AND receiver_id = $1)`;
        const result = await pool.query(query, [senderId, receiverId]);
        return result.rows[0] || null;
    }

    static async getPendingInvitesForUser(userId: string) {
        const query = `
            SELECT i.id, i.sender_id, u.username AS sender_username, p.avatar_url AS sender_avatar, i.created_at
            FROM invites i
            JOIN users u ON i.sender_id = u.id
            LEFT JOIN profiles p ON u.id = p.user_id
            WHERE i.receiver_id = $1 AND i.status = 'pending'
            ORDER BY i.created_at DESC`;
        const result = await pool.query(query, [userId]);
        return result.rows;
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