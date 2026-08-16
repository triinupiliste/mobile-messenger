import { Pool } from 'pg';
import dotenv from 'dotenv';

dotenv.config();

const pool = new Pool({
    host: process.env.DB_HOST || 'localhost',
    port: parseInt(process.env.DB_PORT || '5432', 10),
    user: process.env.DB_USER || 'messenger_user',
    password: process.env.DB_PASSWORD || 'messenger_password',
    database: process.env.DB_NAME || 'messenger_db',
});

export default pool;