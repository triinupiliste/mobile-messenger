import admin from 'firebase-admin';

// Firebase Admin needs a service account credential to send pushes. We look
// for it at the path given by GOOGLE_APPLICATION_CREDENTIALS (Firebase's
// standard auto-detected env var). Until the user creates a Firebase project
// and drops the generated service-account JSON at that path, push sending is
// simply disabled (no-op) instead of crashing the server.
let pushEnabled = false;

try {
    const credentialsPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
    if (credentialsPath && require('fs').existsSync(credentialsPath)) {
        admin.initializeApp({
            credential: admin.credential.applicationDefault(),
        });
        pushEnabled = true;
        console.log('✅ Firebase Admin initialized — push notifications enabled.');
    } else {
        console.warn(
            '⚠️  Firebase service account not found at GOOGLE_APPLICATION_CREDENTIALS — ' +
            'push notifications are disabled until it is configured.'
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
