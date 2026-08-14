import { Request, Response } from 'express';
import fs from 'fs';
import path from 'path';
import { UPLOAD_DIR, generateStoredFilename } from '../middleware/upload.middleware';
import { encryptBuffer, decryptBuffer } from '../utils/encryption.util';

const MIME_TYPES_BY_EXTENSION: Record<string, string> = {
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.png': 'image/png',
    '.gif': 'image/gif',
    '.webp': 'image/webp',
    '.mp4': 'video/mp4',
    '.mov': 'video/quicktime',
    '.avi': 'video/x-msvideo',
    '.mkv': 'video/x-matroska',
    '.webm': 'video/webm',
    '.m4v': 'video/x-m4v',
    '.3gp': 'video/3gpp',
    '.mp3': 'audio/mpeg',
    '.m4a': 'audio/mp4',
    '.wav': 'audio/wav',
    '.aac': 'audio/aac',
    '.ogg': 'audio/ogg',
};

export class MediaController {
    static async uploadMedia(req: Request, res: Response): Promise<void> {
        const file = (req as any).file as Express.Multer.File | undefined;

        if (!file) {
            res.status(400).json({ error: 'No file was uploaded.' });
            return;
        }

        // Encrypt the raw file bytes before they ever touch disk.
        const filename = generateStoredFilename(file.originalname);
        const encrypted = encryptBuffer(file.buffer);
        await fs.promises.writeFile(path.join(UPLOAD_DIR, filename), encrypted);

        const baseUrl = `${req.protocol}://${req.get('host')}`;
        const url = `${baseUrl}/uploads/${filename}`;

        res.status(201).json({ url });
    }

    // Decrypts a stored media file on the fly and streams it back. This replaces
    // serving the /uploads directory directly via express.static, since the files
    // on disk are now encrypted and can no longer be sent as-is.
    static async getMedia(req: Request, res: Response): Promise<void> {
        const filename = req.params.filename;

        // Guard against path traversal — only allow plain filenames we generated ourselves.
        if (!filename || filename.includes('/') || filename.includes('\\') || filename.includes('..')) {
            res.status(400).json({ error: 'Invalid file name.' });
            return;
        }

        const filePath = path.join(UPLOAD_DIR, filename);
        try {
            const encrypted = await fs.promises.readFile(filePath);
            const decrypted = decryptBuffer(encrypted);
            const contentType = MIME_TYPES_BY_EXTENSION[path.extname(filename).toLowerCase()] || 'application/octet-stream';
            res.setHeader('Content-Type', contentType);
            res.setHeader('Cache-Control', 'private, max-age=86400');
            res.status(200).send(decrypted);
        } catch (error) {
            res.status(404).json({ error: 'File not found.' });
        }
    }
}
