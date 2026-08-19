import admin from 'firebase-admin';
import fs from 'fs';
import { logger } from '../utils/logger.util';

// Locally uses GOOGLE_APPLICATION_CREDENTIALS (mounted file); Railway can't
// mount files, so it uses a base64 env var instead. Push is a no-op until either is set.
let pushEnabled = false;

try {
    const base64Credentials = process.env.FIREBASE_SERVICE_ACCOUNT_BASE64;
    const credentialsPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;

    if (base64Credentials) {
        // Strip characters that commonly sneak in when pasting into a web UI env
        // editor (quotes, newlines, soft-wraps) — all invalid in base64.
        const cleaned = base64Credentials.trim().replace(/^['"]|['"]$/g, '').replace(/\s+/g, '');
        let serviceAccount: unknown;
        try {
            serviceAccount = JSON.parse(Buffer.from(cleaned, 'base64').toString('utf-8'));
        } catch (parseError) {
            throw new Error(
                'FIREBASE_SERVICE_ACCOUNT_BASE64 did not decode to valid JSON — re-copy it fresh ' +
                'with `base64 -w0 secrets/firebase-service-account.json` and make sure no quotes, ' +
                'spaces, or line breaks were added when pasting it into Railway.',
            );
        }
        admin.initializeApp({
            credential: admin.credential.cert(serviceAccount as admin.ServiceAccount),
        });
        pushEnabled = true;
        logger.info('Firebase Admin initialized from FIREBASE_SERVICE_ACCOUNT_BASE64 — push notifications enabled.');
    } else if (credentialsPath && fs.existsSync(credentialsPath)) {
        admin.initializeApp({
            credential: admin.credential.applicationDefault(),
        });
        pushEnabled = true;
        logger.info('Firebase Admin initialized — push notifications enabled.');
    } else {
        logger.warn(
            'No Firebase credentials found (checked FIREBASE_SERVICE_ACCOUNT_BASE64 and ' +
            'GOOGLE_APPLICATION_CREDENTIALS) — push notifications are disabled until one is configured.'
        );
    }
} catch (error) {
    logger.error('Failed to initialize Firebase Admin — push notifications are disabled.', error);
}

export interface PushPayload {
    title: string;
    body: string;
    data?: Record<string, string>;
}

export class PushService {
    // Failures (invalid token, Firebase not configured, network error) are
    // logged and swallowed — a failed push must never break the triggering flow.
    static async sendToToken(fcmToken: string | null | undefined, payload: PushPayload): Promise<void> {
        if (!pushEnabled || !fcmToken) return;

        try {
            await admin.messaging().send({
                token: fcmToken,
                // Data-only (no `notification` block) so the app renders it itself with a
                // stable per-chat id — needed so the tray notification can be cancelled on read.
                data: {
                    ...payload.data,
                    title: payload.title,
                    body: payload.body,
                },
                android: {
                    priority: 'high',
                },
            });
        } catch (error) {
            logger.error('Failed to send push notification:', error);
        }
    }
}
