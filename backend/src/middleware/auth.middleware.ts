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