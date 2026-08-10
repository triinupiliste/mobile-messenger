import pool from '../config/database';
import { User, Profile } from '../models/user.model';
import { encryptText, decryptText } from '../utils/encryption.util';

export class UserRepository {
    static async findByEmailOrUsername(email: string, username: string): Promise<User | null> {
        const query = 'SELECT * FROM users WHERE email = $1 OR username = $2';
        const result = await pool.query(query, [email, username]);
        return result.rows[0] || null;
    }

    static async createUser(email: string, username: string, passwordHash: string): Promise<User> {
        const client = await pool.connect();
        try {
            await client.query('BEGIN');
            const userQuery = `
                INSERT INTO users (email, username, password_hash) 
                VALUES ($1, $2, $3) RETURNING *`;
            const userResult = await client.query(userQuery, [email, username, passwordHash]);
            const user: User = userResult.rows[0];

            // Create blank profile for the new user
            await client.query('INSERT INTO profiles (user_id) VALUES ($1)', [user.id]);
            await client.query('COMMIT');
            return user;
        } catch (error) {
            await client.query('ROLLBACK');
            throw error;
        } finally {
            client.release();
        }
    }

    static async getProfile(userId: string): Promise<Profile | null> {
        const query = 'SELECT * FROM profiles WHERE user_id = $1';
        const result = await pool.query(query, [userId]);
        if (!result.rows[0]) return null;

        const profile: Profile = result.rows[0];
        // Decrypt sensitive about_me data fetched from DB
        if (profile.about_me) {
            profile.about_me = decryptText(profile.about_me);
        }
        return profile;
    }

    static async updateProfile(userId: string, avatarUrl?: string, aboutMe?: string): Promise<Profile> {
        // Encrypt aboutMe before writing to DB as per data encryption requirements
        const encryptedAboutMe = aboutMe ? encryptText(aboutMe) : null;

        const query = `
            UPDATE profiles 
            SET avatar_url = COALESCE($2, avatar_url), 
                about_me = COALESCE($3, about_me)
            WHERE user_id = $1 
            RETURNING *`;
        const result = await pool.query(query, [userId, avatarUrl, encryptedAboutMe]);
        const profile: Profile = result.rows[0];
        if (profile.about_me) profile.about_me = decryptText(profile.about_me);
        return profile;
    }

    static async searchUsers(searchTerm: string, currentUserId: string): Promise<User[]> {
        const query = `
            SELECT id, email, username, created_at FROM users 
            WHERE (email ILIKE $1 OR username ILIKE $1) AND id != $2
            LIMIT 10`;
        const result = await pool.query(query, [`%${searchTerm}%`, currentUserId]);
        return result.rows;
    }
}