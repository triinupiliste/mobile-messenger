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
