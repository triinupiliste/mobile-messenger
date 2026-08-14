import pool from '../config/database';
import { User, Profile } from '../models/user.model';
import { encryptText, decryptText } from '../utils/encryption.util';

export class UserRepository {
    static async findByEmailOrUsername(email: string, username: string): Promise<User | null> {
        const query = 'SELECT * FROM users WHERE email = $1 OR username = $2';
        const result = await pool.query(query, [email, username]);
        return result.rows[0] || null;
    }

    // Same lookup as above but excludes the given user, so a profile update can
    // check for collisions with *other* accounts without flagging the user's
    // own unchanged email/username as "already taken".
    static async findByEmailOrUsernameExcludingUser(
        email: string,
        username: string,
        excludeUserId: string,
    ): Promise<User | null> {
        const query = 'SELECT * FROM users WHERE (email = $1 OR username = $2) AND id != $3';
        const result = await pool.query(query, [email, username, excludeUserId]);
        return result.rows[0] || null;
    }

    static async createUser(
        email: string,
        username: string,
        passwordHash: string,
        verificationToken: string,
        verificationTokenExpires: Date,
    ): Promise<User> {
        const client = await pool.connect();
        try {
            await client.query('BEGIN');
            const userQuery = `
                INSERT INTO users (
                    email, username, password_hash,
                    verification_token, verification_token_expires
                )
                VALUES ($1, $2, $3, $4, $5) RETURNING *`;
            const userResult = await client.query(userQuery, [
                email,
                username,
                passwordHash,
                verificationToken,
                verificationTokenExpires,
            ]);
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
        const query = `
            SELECT u.id, u.id AS user_id, u.email, u.username,
                   p.avatar_url, p.about_me
            FROM users u
            LEFT JOIN profiles p ON u.id = p.user_id
            WHERE u.id = $1`;
        const result = await pool.query(query, [userId]);
        if (!result.rows[0]) return null;

        const profile: Profile = result.rows[0];
        // Decrypt sensitive profile data fetched from DB
        if (profile.avatar_url) {
            profile.avatar_url = decryptText(profile.avatar_url);
        }
        if (profile.about_me) {
            profile.about_me = decryptText(profile.about_me);
        }
        return profile;
    }

    static async updateProfile(
        userId: string,
        updates: { username?: string; email?: string; avatarUrl?: string; aboutMe?: string },
    ): Promise<Profile> {
        const { username, email, avatarUrl, aboutMe } = updates;
        // Encrypt avatarUrl/aboutMe before writing to DB as per data encryption requirements
        const encryptedAvatarUrl = avatarUrl ? encryptText(avatarUrl) : null;
        const encryptedAboutMe = aboutMe ? encryptText(aboutMe) : null;

        const client = await pool.connect();
        try {
            await client.query('BEGIN');

            await client.query(
                `UPDATE users
                 SET username = COALESCE($2, username),
                     email = COALESCE($3, email)
                 WHERE id = $1`,
                [userId, username ?? null, email ?? null],
            );

            await client.query(
                `UPDATE profiles
                 SET avatar_url = COALESCE($2, avatar_url),
                     about_me = COALESCE($3, about_me)
                 WHERE user_id = $1`,
                [userId, encryptedAvatarUrl, encryptedAboutMe],
            );

            const result = await client.query(
                `SELECT u.id, u.id AS user_id, u.email, u.username, p.avatar_url, p.about_me
                 FROM users u
                 LEFT JOIN profiles p ON u.id = p.user_id
                 WHERE u.id = $1`,
                [userId],
            );

            await client.query('COMMIT');

            const profile: Profile = result.rows[0];
            if (profile.avatar_url) profile.avatar_url = decryptText(profile.avatar_url);
            if (profile.about_me) profile.about_me = decryptText(profile.about_me);
            return profile;
        } catch (error) {
            await client.query('ROLLBACK');
            throw error;
        } finally {
            client.release();
        }
    }

    static async searchUsers(searchTerm: string, currentUserId: string): Promise<User[]> {
        const query = `
            SELECT u.id, u.email, u.username, u.created_at, p.avatar_url
            FROM users u
            LEFT JOIN profiles p ON u.id = p.user_id
            WHERE (u.email ILIKE $1 OR u.username ILIKE $1) AND u.id != $2
            ORDER BY u.username
            LIMIT 10`;
        const result = await pool.query(query, [`%${searchTerm}%`, currentUserId]);
        return result.rows.map((row: any) => ({
            ...row,
            avatar_url: row.avatar_url ? decryptText(row.avatar_url) : row.avatar_url,
        }));
    }

    static async existsById(userId: string): Promise<boolean> {
        const result = await pool.query('SELECT 1 FROM users WHERE id = $1', [userId]);
        return result.rowCount === 1;
    }

    static async verifyEmail(verificationToken: string): Promise<User | null> {
        const query = `
            UPDATE users
            SET is_verified = TRUE,
                verification_token = NULL,
                verification_token_expires = NULL
            WHERE verification_token = $1
              AND verification_token_expires > CURRENT_TIMESTAMP
              AND is_verified = FALSE
            RETURNING *`;
        const result = await pool.query(query, [verificationToken]);
        return result.rows[0] || null;
    }

    static async setVerificationToken(
        userId: string,
        verificationToken: string,
        verificationTokenExpires: Date,
    ): Promise<void> {
        await pool.query(
            `UPDATE users
             SET verification_token = $2, verification_token_expires = $3
             WHERE id = $1 AND is_verified = FALSE`,
            [userId, verificationToken, verificationTokenExpires],
        );
    }

    static async setResetToken(
        userId: string,
        resetTokenHash: string,
        resetTokenExpires: Date,
    ): Promise<void> {
        await pool.query(
            `UPDATE users
             SET reset_token = $2, reset_token_expires = $3
             WHERE id = $1`,
            [userId, resetTokenHash, resetTokenExpires],
        );
    }

    // Looks up a user by reset token hash without consuming it, so the reset
    // form can be shown (or rejected as invalid/expired) before a new password
    // is submitted.
    static async findByValidResetToken(resetTokenHash: string): Promise<User | null> {
        const query = `
            SELECT * FROM users
            WHERE reset_token = $1
              AND reset_token_expires > CURRENT_TIMESTAMP`;
        const result = await pool.query(query, [resetTokenHash]);
        return result.rows[0] || null;
    }

    // Atomically consumes the reset token: only succeeds if it's still valid
    // and unexpired, and clears it afterwards so it can't be replayed.
    static async resetPassword(resetTokenHash: string, passwordHash: string): Promise<User | null> {
        const query = `
            UPDATE users
            SET password_hash = $2,
                reset_token = NULL,
                reset_token_expires = NULL
            WHERE reset_token = $1
              AND reset_token_expires > CURRENT_TIMESTAMP
            RETURNING *`;
        const result = await pool.query(query, [resetTokenHash, passwordHash]);
        return result.rows[0] || null;
    }
}