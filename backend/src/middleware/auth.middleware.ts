import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';

export function verifyToken(req: Request, res: Response, next: NextFunction): void {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1]; // Expecting "Bearer <TOKEN>"

    if (!token) {
        res.status(401).json({ error: 'Access token missing or malformed.' });
        return;
    }

    jwt.verify(token, process.env.JWT_SECRET || 'fallback_secret', (err: any, user: any) => {
        if (err) {
            res.status(403).json({ error: 'Token is invalid or expired.' });
            return;
        }
        (req as any).user = user;
        next();
    });
}

// Same as verifyToken, but also accepts the JWT via a `?token=` query parameter.
// Needed for the /uploads/:filename endpoint: native media widgets (Image,
// VideoPlayerController, video_thumbnail, audioplayers) load media by URL and
// can't attach an Authorization header, so the token travels in the URL instead.
export function verifyMediaToken(req: Request, res: Response, next: NextFunction): void {
    const authHeader = req.headers['authorization'];
    const headerToken = authHeader && authHeader.split(' ')[1];
    const queryToken = typeof req.query.token === 'string' ? req.query.token : undefined;
    const token = headerToken || queryToken;

    if (!token) {
        res.status(401).json({ error: 'Access token missing or malformed.' });
        return;
    }

    jwt.verify(token, process.env.JWT_SECRET || 'fallback_secret', (err: any, user: any) => {
        if (err) {
            res.status(403).json({ error: 'Token is invalid or expired.' });
            return;
        }
        (req as any).user = user;
        next();
    });
}