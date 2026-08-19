import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { JWT_SECRET } from '../config/env';
import { UserRepository } from '../repositories/user.repository';

// Recognized by the Flutter app's AuthProvider/ApiService to force a local
// logout instead of showing a generic "session expired" error.
const SESSION_INVALIDATED_RESPONSE = {
    error: 'You have been logged out because your account was signed in on another device.',
    code: 'SESSION_INVALIDATED',
};

// A version mismatch means the account logged in on another device since
// this token was issued. Tokens without an `sv` claim (pre-feature) are treated as version 0.
async function hasValidSessionVersion(decoded: any): Promise<boolean> {
    const tokenVersion = typeof decoded.sv === 'number' ? decoded.sv : 0;
    const currentVersion = await UserRepository.getSessionVersion(decoded.userId);
    return currentVersion !== null && currentVersion === tokenVersion;
}

export function verifyToken(req: Request, res: Response, next: NextFunction): void {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1]; // Expecting "Bearer <TOKEN>"

    if (!token) {
        res.status(401).json({ error: 'Access token missing or malformed.' });
        return;
    }

    jwt.verify(token, JWT_SECRET, (err: any, decoded: any) => {
        if (err) {
            res.status(403).json({ error: 'Token is invalid or expired.' });
            return;
        }
        hasValidSessionVersion(decoded).then((valid) => {
            if (!valid) {
                res.status(401).json(SESSION_INVALIDATED_RESPONSE);
                return;
            }
            (req as any).user = decoded;
            next();
        }).catch(() => {
            res.status(500).json({ error: 'Internal server error during authentication.' });
        });
    });
}

// Same as verifyToken, but also accepts the JWT via ?token= — native media
// widgets (Image, VideoPlayerController, etc.) load by URL and can't set headers.
export function verifyMediaToken(req: Request, res: Response, next: NextFunction): void {
    const authHeader = req.headers['authorization'];
    const headerToken = authHeader && authHeader.split(' ')[1];
    const queryToken = typeof req.query.token === 'string' ? req.query.token : undefined;
    const token = headerToken || queryToken;

    if (!token) {
        res.status(401).json({ error: 'Access token missing or malformed.' });
        return;
    }

    jwt.verify(token, JWT_SECRET, (err: any, decoded: any) => {
        if (err) {
            res.status(403).json({ error: 'Token is invalid or expired.' });
            return;
        }
        hasValidSessionVersion(decoded).then((valid) => {
            if (!valid) {
                res.status(401).json(SESSION_INVALIDATED_RESPONSE);
                return;
            }
            (req as any).user = decoded;
            next();
        }).catch(() => {
            res.status(500).json({ error: 'Internal server error during authentication.' });
        });
    });
}