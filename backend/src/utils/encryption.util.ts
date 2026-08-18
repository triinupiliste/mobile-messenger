import crypto from 'crypto';
import { ENCRYPTION_KEY } from '../config/env';

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
        // encryptText() always produces an "iv:ciphertext" pair, so reaching this
        // branch means the stored value never went through encryptText() (e.g.
        // legacy/manually-inserted data). Log it so any accidental plaintext
        // write is visible instead of silently passing through unnoticed.
        console.warn('decryptText: value is not in the expected iv:ciphertext format, returning as-is.');
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

// Binary-safe variants for encrypting file contents (images, video, audio) at rest.
// The IV is stored as the first 16 bytes of the output so it travels alongside
// the ciphertext without needing a separate text-based encoding like encryptText does.
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

// AES-256-CBC (used above) picks a random IV per call, so the same input
// never produces the same ciphertext twice — that's what makes it secure,
// but it also means encrypted columns can't be searched/matched with plain
// SQL (`=`/ILIKE) directly. For fields that must stay encrypted at rest but
// also need an exact-match lookup (e.g. finding a user by email for login,
// or enforcing "email already in use"), we additionally store a deterministic
// HMAC-SHA256 of the normalized value in a separate `*_hash` column. HMAC is
// one-way (can't be reversed to recover the original value) and, unlike a
// plain hash, requires ENCRYPTION_KEY to compute — so it can't be brute-forced
// offline from the database alone the way an unsalted SHA-256 lookup table
// could be. Callers must normalize (trim + lowercase) the value themselves
// before calling this, so the same email always hashes identically.
export function hashForLookup(normalizedValue: string): string {
    return crypto.createHmac('sha256', ENCRYPTION_KEY).update(normalizedValue).digest('hex');
}