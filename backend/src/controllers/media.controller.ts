import { Request, Response } from 'express';

export class MediaController {
    static async uploadMedia(req: Request, res: Response): Promise<void> {
        const file = (req as any).file as Express.Multer.File | undefined;

        if (!file) {
            res.status(400).json({ error: 'No file was uploaded.' });
            return;
        }

        const baseUrl = `${req.protocol}://${req.get('host')}`;
        const url = `${baseUrl}/uploads/${file.filename}`;

        res.status(201).json({ url });
    }
}
