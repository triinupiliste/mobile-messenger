// Fails fast on startup if a required secret is missing, instead of silently
// falling back to an insecure/ephemeral default. A missing ENCRYPTION_KEY
// used to make encryption.util.ts generate a new random key on every process
// boot, permanently breaking decryption of anything encrypted under a
// previous key (avatar_url, about_me, message content, etc.) after every
// restart/redeploy. A missing JWT_SECRET used to fall back to a hardcoded
// string ('fallback_secret') that's visible in the public source code,
// letting anyone forge login tokens.
function requireEnv(name: string): string {
    const value = process.env[name];
    if (!value) {
        throw new Error(
            `Missing required environment variable: ${name}. Set it in your ` +
            `environment (e.g. Railway's Variables tab, or docker-compose.yml ` +
            `for local dev) before starting the server.`,
        );
    }
    return value;
}

export const JWT_SECRET = requireEnv('JWT_SECRET');
export const ENCRYPTION_KEY = requireEnv('ENCRYPTION_KEY');

// Origins allowed to call the REST API and connect over Socket.IO. The
// Flutter app itself doesn't send an `Origin` header (that's a
// browser-only concept), so this only matters for browser-based callers —
// it stops an arbitrary web page from making authenticated requests/socket
// connections against this API on a victim's behalf. Defaults cover the
// hosted backend plus local development; override with a comma-separated
// list via the ALLOWED_ORIGINS env var if you deploy somewhere else.
const DEFAULT_ALLOWED_ORIGINS = [
    'https://mobile-messenger-production.up.railway.app',
    'http://localhost:5000',
    'http://127.0.0.1:5000',
];

export const ALLOWED_ORIGINS = process.env.ALLOWED_ORIGINS
    ? process.env.ALLOWED_ORIGINS.split(',').map((origin) => origin.trim())
    : DEFAULT_ALLOWED_ORIGINS;
