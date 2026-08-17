import admin from 'firebase-admin';
import fs from 'fs';

// Firebase Admin needs a service account credential to send pushes. Locally,
// docker-compose mounts backend/secrets and points GOOGLE_APPLICATION_CREDENTIALS
// at the mounted JSON file. That file is gitignored (it's a credential) and
// never reaches managed hosts like Railway, which can't mount a local file
// anyway — so on Railway the credential is instead supplied as a
// base64-encoded env var (FIREBASE_SERVICE_ACCOUNT_BASE64) and decoded here.
// Until one of the two is configured, push sending is simply disabled
// (no-op) instead of crashing the server.
let pushEnabled = false;

try {
    const base64Credentials = process.env.FIREBASE_SERVICE_ACCOUNT_BASE64;
    const credentialsPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;

    if (base64Credentials) {
        const serviceAccount = JSON.parse(Buffer.from(base64Credentials, 'base64').toString('utf-8'));
        admin.initializeApp({
            credential: admin.credential.cert(serviceAccount),
        });
        pushEnabled = true;
        console.log('✅ Firebase Admin initialized from FIREBASE_SERVICE_ACCOUNT_BASE64 — push notifications enabled.');
    } else if (credentialsPath && fs.existsSync(credentialsPath)) {
        admin.initializeApp({
            credential: admin.credential.applicationDefault(),
        });
        pushEnabled = true;
        console.log('✅ Firebase Admin initialized — push notifications enabled.');
    } else {
        console.warn(
            '⚠️  No Firebase credentials found (checked FIREBASE_SERVICE_ACCOUNT_BASE64 and ' +
            'GOOGLE_APPLICATION_CREDENTIALS) — push notifications are disabled until one is configured.'
        );
    }
} catch (error) {
    console.error('⚠️  Failed to initialize Firebase Admin — push notifications are disabled.', error);
}

export interface PushPayload {
    title: string;
    body: string;
    data?: Record<string, string>;
}

export class PushService {
    // Sends a push notification to a single device token. Failures (invalid/
    // stale token, Firebase not configured, network error, etc.) are logged
    // and swallowed — a failed push must never break the message/invite flow
    // that triggered it.
    static async sendToToken(fcmToken: string | null | undefined, payload: PushPayload): Promise<void> {
        if (!pushEnabled || !fcmToken) return;

        try {
            await admin.messaging().send({
                token: fcmToken,
                // Data-only (no top-level `notification` block) so the OS never
                // auto-displays this itself — the app always renders it via its
                // own code, using a stable per-chat notification id. That's what
                // lets a chat's tray notification actually get cancelled once
                // it's read, instead of being stuck there until swiped away.
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
            console.error('Failed to send push notification:', error);
        }
    }
}
