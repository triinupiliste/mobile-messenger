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

// Files are encrypted (see MediaController.uploadMedia) before they're written to
// disk, so multer only needs to buffer the raw upload in memory rather than
// writing plaintext straight to disk itself.
// 20MB limit to match the app's client-side media size check
export const uploadMedia = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: 20 * 1024 * 1024 },
});

// Profile pictures are restricted to JPEG/PNG and a smaller 5MB limit, unlike
// general chat media (images/video/audio) which allow more formats and a
// larger 20MB limit above.
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

