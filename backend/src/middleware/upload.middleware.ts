import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
import multer from 'multer';

export const UPLOAD_DIR = path.join(__dirname, '..', '..', 'uploads');

if (!fs.existsSync(UPLOAD_DIR)) {
    fs.mkdirSync(UPLOAD_DIR, { recursive: true });
}

export function generateStoredFilename(originalName: string): string {
    return `${Date.now()}-${crypto.randomBytes(8).toString('hex')}${path.extname(originalName)}`;
}

// Files are encrypted (see MediaController.uploadMedia) before they're written to
// disk, so multer only needs to buffer the raw upload in memory rather than
// writing plaintext straight to disk itself.
// 20MB limit to match the app's client-side media size check
export const uploadMedia = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: 20 * 1024 * 1024 },
});
