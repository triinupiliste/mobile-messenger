import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
import multer from 'multer';
import { Request, Response, NextFunction } from 'express';

export const UPLOAD_DIR = path.join(__dirname, '..', '..', 'uploads');

if (!fs.existsSync(UPLOAD_DIR)) {
    fs.mkdirSync(UPLOAD_DIR, { recursive: true });
}

export function generateStoredFilename(originalName: string): string {
    return `${Date.now()}-${crypto.randomBytes(8).toString('hex')}${path.extname(originalName)}`;
}

// Buffers in memory; files are encrypted before disk write (see MediaController).
// 150MB covers a raw video upload before server-side compression brings it under 20MB.
export const uploadMedia = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: 150 * 1024 * 1024 },
});

// Profile pictures are restricted to JPEG/PNG and 5MB, unlike general chat
// media which allows more formats and a 20MB limit.
const AVATAR_ALLOWED_MIME_TYPES = ['image/jpeg', 'image/png'];

const avatarUpload = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: 5 * 1024 * 1024 },
    fileFilter: (_req, file, cb) => {
        if (!AVATAR_ALLOWED_MIME_TYPES.includes(file.mimetype)) {
            cb(new Error('Only JPEG and PNG images are allowed for profile pictures.'));
            return;
        }
        cb(null, true);
    },
});

// Wraps multer so file-type/size rejections come back as a clean 400 response
// instead of falling through to the generic error handler.
export function uploadAvatar(req: Request, res: Response, next: NextFunction): void {
    avatarUpload.single('file')(req, res, (err: unknown) => {
        if (err) {
            const message = err instanceof multer.MulterError && err.code === 'LIMIT_FILE_SIZE'
                ? 'Profile pictures must be 5MB or smaller.'
                : (err as Error).message || 'Invalid file upload.';
            res.status(400).json({ error: message });
            return;
        }
        next();
    });
}

