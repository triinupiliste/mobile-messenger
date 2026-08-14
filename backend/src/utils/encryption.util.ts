import crypto from 'crypto';

const ENCRYPTION_KEY = process.env.ENCRYPTION_KEY || crypto.randomBytes(32).toString('hex'); // Must be 32 bytes hex or string
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
    if (parts.length !== 2) return text; // Fallback if unencrypted
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