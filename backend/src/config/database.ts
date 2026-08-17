import { Pool } from 'pg';
import dotenv from 'dotenv';

dotenv.config();

// Use connectionString if available (Railway/Production), otherwise fall back to local vars
const isProduction = process.env.NODE_ENV === 'production' || process.env.DATABASE_URL;

const pool = new Pool(
    isProduction
        ? {
              connectionString: process.env.DATABASE_URL,
              ssl: {
                  rejectUnauthorized: false, // Required for cloud databases like Railway
              },
          }
        : {
              host: process.env.DB_HOST || 'localhost',
              port: parseInt(process.env.DB_PORT || '5432', 10),
              user: process.env.DB_USER || 'messenger_user',
              password: process.env.DB_PASSWORD || 'messenger_password',
              database: process.env.DB_NAME || 'messenger_db',
          }
);

export default pool;