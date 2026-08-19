import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { JWT_SECRET } from '../config/env';
import { UserRepository } from '../repositories/user.repository';

// A logged-in-elsewhere response shape the frontend recognizes to force a
// local logout (see AuthProvider/ApiService on the Flutter side) rather than
// just showing a generic "session expired" error.
const SESSION_INVALIDATED_RESPONSE = {
    error: 'You have been logged out because your account was signed in on another device.',
    code: 'SESSION_INVALIDATED',
};

// Confirms the JWT's embedded session version still matches the account's
// current one in the database. A mismatch means the account has since logged
// in on another device (which bumps the version), so this token — even
// though it's a validly-signed, unexpired JWT — is no longer the active
// session and must be rejected. Tokens issued before this feature existed
// have no `sv` claim; treated as version 0 so they keep working until the
// next login bumps the column past that.
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