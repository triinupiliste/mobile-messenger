import fs from 'fs';
import path from 'path';
import pool from './database';
import { encryptText, hashForLookup } from '../utils/encryption.util';

// Idempotently creates the schema on a fresh database. The local Docker
// Postgres auto-runs init.sql via docker-entrypoint-initdb.d on its very
// first boot, but managed hosts like Railway don't have that mechanism —
// their database starts out completely empty. Running this on every server
// startup makes a fresh deploy (Railway, or anywhere else) self-initializing
// instead of requiring the schema to be pasted into a SQL console by hand.
// Safe to call every time: it only executes init.sql if the `users` table
// doesn't exist yet.
export async function runMigrations(): Promise<void> {
    const { rows } = await pool.query("SELECT to_regclass('public.users') AS exists");
    if (rows[0]?.exists) {
        console.log('Database schema already initialized, skipping migration.');
    } else {
        console.log('No existing schema found — running init.sql to create tables...');
        const initSqlPath = path.join(__dirname, '../../database/init.sql');
        const initSql = fs.readFileSync(initSqlPath, 'utf-8');
        await pool.query(initSql);
        console.log('Database schema created successfully.');
    }

    await ensureEmailEncryption();
}

// Encrypts any plaintext emails left over from before email encryption was
// added (older deployments that already have real user rows). Safe to run on
// every startup: it adds the email_hash column if missing, then only touches
// rows that don't have a hash yet, so already-migrated rows are never
// re-encrypted. New installs run init.sql (which already has email_hash) and
// start out with zero users, so this is a fast no-op for them.
async function ensureEmailEncryption(): Promise<void> {
    await pool.query('ALTER TABLE users ADD COLUMN IF NOT EXISTS email_hash VARCHAR(64)');
    await pool.query('CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email_hash ON users(email_hash)');

    const { rows } = await pool.query('SELECT id, email FROM users WHERE email_hash IS NULL');
    for (const row of rows) {
        const normalizedEmail = row.email.trim().toLowerCase();
        await pool.query('UPDATE users SET email = $2, email_hash = $3 WHERE id = $1', [
            row.id,
            encryptText(row.email),
            hashForLookup(normalizedEmail),
        ]);
    }
    if (rows.length > 0) {
        console.log(`Encrypted ${rows.length} plaintext user email(s) at rest.`);
    }
}
