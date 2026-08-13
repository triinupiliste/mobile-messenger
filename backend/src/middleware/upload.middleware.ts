import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
import multer from 'multer';

export const UPLOAD_DIR = path.join(__dirname, '..', '..', 'uploads');

if (!fs.existsSync(UPLOAD_DIR)) {
    fs.mkdirSync(UPLOAD_DIR, { recursive: true });
}

const storage = multer.diskStorage({
    destination: (_req, _file, cb) => cb(null, UPLOAD_DIR),
    filename: (_req, file, cb) => {
        const uniqueName = `${Date.now()}-${crypto.randomBytes(8).toString('hex')}${path.extname(file.originalname)}`;
        cb(null, uniqueName);
    },
});

// 20MB limit to match the app's client-side media size check
export const uploadMedia = multer({
    storage,
    limits: { fileSize: 20 * 1024 * 1024 },
});
