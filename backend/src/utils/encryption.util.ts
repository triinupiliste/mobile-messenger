import crypto from 'crypto';
import { ENCRYPTION_KEY } from '../config/env';
import { logger } from './logger.util';

const IV_LENGTH = 16; // AES block size

export function encryptText(text: string): string {
    const iv = crypto.randomBytes(IV_LENGTH);
    const key = crypto.scryptSync(ENCRYPTION_KEY, 'salt', 32);
    const cipher = crypto.createCipheriv('aes-256-cbc', key, iv);
    let encrypted = cipher.update(text, 'utf8', 'hex');
    encrypted += cipher.final('hex');
    return `${iv.toString('hex')}:${encrypted}`;
}

export function decryptText(text: string): string {
    const parts = text.split(':');
    if (parts.length !== 2) {
        // Reaching here means the value never went through encryptText() (e.g.
        // legacy/manually-inserted data) — log it so accidental plaintext writes are visible.
        logger.warn('decryptText: value is not in the expected iv:ciphertext format, returning as-is.');
        return text;
    }
    const iv = Buffer.from(parts[0], 'hex');
    const encryptedText = parts[1];
    const key = crypto.scryptSync(ENCRYPTION_KEY, 'salt', 32);
    const decipher = crypto.createDecipheriv('aes-256-cbc', key, iv);
    let decrypted = decipher.update(encryptedText, 'hex', 'utf8');
    decrypted += decipher.final('utf8');
    return decrypted;
}

// Binary-safe variants for encrypting file contents at rest. IV is stored as
// the first 16 bytes of output rather than a separate text encoding.
export function encryptBuffer(buffer: Buffer): Buffer {
    const iv = crypto.randomBytes(IV_LENGTH);
    const key = crypto.scryptSync(ENCRYPTION_KEY, 'salt', 32);
    const cipher = crypto.createCipheriv('aes-256-cbc', key, iv);
    const encrypted = Buffer.concat([cipher.update(buffer), cipher.final()]);
    return Buffer.concat([iv, encrypted]);
}

export function decryptBuffer(buffer: Buffer): Buffer {
    const iv = buffer.subarray(0, IV_LENGTH);
    const encrypted = buffer.subarray(IV_LENGTH);
    const key = crypto.scryptSync(ENCRYPTION_KEY, 'salt', 32);
    const decipher = crypto.createDecipheriv('aes-256-cbc', key, iv);
    return Buffer.concat([decipher.update(encrypted), decipher.final()]);
}

// Deterministic HMAC-SHA256 for exact-match lookups on encrypted columns
// (AES's IV means they can't be matched with `=`). Keyed by ENCRYPTION_KEY so it can't be brute-forced from the DB alone.
export function hashForLookup(normalizedValue: string): string {
    return crypto.createHmac('sha256', ENCRYPTION_KEY).update(normalizedValue).digest('hex');
}

// Decrypts fields in place, skipping null/empty ones — centralizes the
// decrypt-if-present pattern used across repositories. Mutates and returns the same object.
export function decryptFields<T extends Record<string, any>>(
    row: T | null | undefined,
    fields: (keyof T)[],
): T | null | undefined {
    if (!row) return row;
    for (const field of fields) {
        if (row[field]) {
            row[field] = decryptText(row[field] as string) as T[keyof T];
        }
    }
    return row;
}