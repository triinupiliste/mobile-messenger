import fs from 'fs';
import path from 'path';
import pool from './database';

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
        return;
    }

    console.log('No existing schema found — running init.sql to create tables...');
    const initSqlPath = path.join(__dirname, '../../database/init.sql');
    const initSql = fs.readFileSync(initSqlPath, 'utf-8');
    await pool.query(initSql);
    console.log('Database schema created successfully.');
}
