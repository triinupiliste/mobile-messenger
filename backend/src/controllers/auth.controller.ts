import { Request, Response } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { createHash, randomBytes } from 'crypto';
import { UserRepository } from '../repositories/user.repository';
import { validatePasswordStrength, isValidEmail } from '../utils/validator.util';
import { sendVerificationEmail, sendPasswordResetEmail } from '../services/email.service';
import { JWT_SECRET } from '../config/env';

const VERIFICATION_TOKEN_LIFETIME_MS = 24 * 60 * 60 * 1000;
const RESET_TOKEN_LIFETIME_MS = 15 * 60 * 1000;
const BCRYPT_SALT_ROUNDS = 10;

function createVerificationToken(): { rawToken: string; tokenHash: string; expiresAt: Date } {
    const rawToken = randomBytes(32).toString('hex');
    return {
        rawToken,
        tokenHash: createHash('sha256').update(rawToken).digest('hex'),
        expiresAt: new Date(Date.now() + VERIFICATION_TOKEN_LIFETIME_MS),
    };
}

function createResetToken(): { rawToken: string; tokenHash: string; expiresAt: Date } {
    const rawToken = randomBytes(32).toString('hex');
    return {
        rawToken,
        tokenHash: createHash('sha256').update(rawToken).digest('hex'),
        expiresAt: new Date(Date.now() + RESET_TOKEN_LIFETIME_MS),
    };
}

function escapeHtml(value: string): string {
    return value
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

// Shared visual chrome for every page a user can land on by tapping a link in
// an email (verify-email / reset-password). Mirrors the Flutter app's own
// look (Manrope font, sunset-coral gradient badge, rounded "card" surface)
// so the browser hand-off doesn't feel like a jarring, unstyled detour.
const BRAND = {
    background: '#FFF5F2',
    surface: '#FFFFFF',
    primary: '#FF6B6B',
    primaryDark: '#D15858',
    textPrimary: '#2D3142',
    textSecondary: '#8D99AE',
    cardBorder: '#EDEDF2',
    errorBackground: '#FFEBEE',
    errorBorder: '#EF9A9A',
    errorText: '#C62828',
};

const CHECK_ICON = '<svg width="34" height="34" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>';
const ERROR_ICON = '<svg width="30" height="30" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 6 18M6 6l12 12"/></svg>';
const LOCK_ICON = '<svg width="30" height="30" viewBox="0 0 24 24" fill="#fff"><path d="M12 1a5 5 0 0 0-5 5v3H6a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-9a2 2 0 0 0-2-2h-1V6a5 5 0 0 0-5-5Zm-3 8V6a3 3 0 1 1 6 0v3H9Zm3 4a2 2 0 0 1 1 3.73V19a1 1 0 1 1-2 0v-1.27A2 2 0 0 1 12 13Z"/></svg>';

function pageShell(title: string, bodyHtml: string): string {
    return `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title><link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin><link href="https://fonts.googleapis.com/css2?family=Manrope:wght@500;700;800&display=swap" rel="stylesheet"><style>
body{margin:0;font-family:'Manrope',Arial,sans-serif;background:${BRAND.background};color:${BRAND.textPrimary};padding:40px 20px;display:flex;min-height:100vh;box-sizing:border-box}
main{max-width:420px;margin:auto;background:${BRAND.surface};padding:36px 32px;border-radius:24px;box-shadow:0 12px 32px rgba(45,49,66,0.08);text-align:center;width:100%;box-sizing:border-box}
.badge{width:72px;height:72px;border-radius:50%;margin:0 auto 20px;display:flex;align-items:center;justify-content:center;background:linear-gradient(135deg,${BRAND.primary},${BRAND.primaryDark});box-shadow:0 8px 20px rgba(255,107,107,0.35)}
h1{margin:0 0 10px;font-size:22px;font-weight:800}
p{margin:0 0 8px;font-size:15px;line-height:1.5;color:${BRAND.textSecondary}}
.error-banner{background:${BRAND.errorBackground};border:1px solid ${BRAND.errorBorder};color:${BRAND.errorText};border-radius:14px;padding:12px 14px;font-size:14px;font-weight:700;text-align:left;margin:18px 0 0}
form{text-align:left;margin-top:22px}
label{display:block;font-weight:700;font-size:14px;margin:0 0 8px}
input[type=password]{box-sizing:border-box;border:1px solid ${BRAND.cardBorder};background:${BRAND.background};border-radius:14px;font-family:inherit;font-size:16px;padding:14px;width:100%;color:${BRAND.textPrimary}}
input[type=password]:focus{outline:2px solid ${BRAND.primary};outline-offset:1px}
button{background:linear-gradient(135deg,${BRAND.primary},${BRAND.primaryDark});border:0;border-radius:14px;color:#fff;cursor:pointer;font-family:inherit;font-size:16px;font-weight:800;margin-top:20px;padding:14px;width:100%}
</style></head><body><main>${bodyHtml}</main></body></html>`;
}

function verificationPage(title: string, message: string, successful: boolean): string {
    const icon = successful ? CHECK_ICON : ERROR_ICON;
    return pageShell(title, `<div class="badge">${icon}</div><h1>${title}</h1><p>${message}</p><p>You may now return to Mobile Messenger.</p>`);
}

function resetPasswordPage(rawToken: string, errorMessage?: string): string {
    const safeToken = escapeHtml(rawToken);
    const errorBlock = errorMessage
        ? `<div class="error-banner">${escapeHtml(errorMessage)}</div>`
        : '';

    return pageShell('Reset password', `<div class="badge">${LOCK_ICON}</div><h1>Choose a new password</h1><p>Enter a new password for your Mobile Messenger account.</p>${errorBlock}<form method="post" action="/api/auth/reset-password"><input type="hidden" name="token" value="${safeToken}"><label for="password">New password</label><input id="password" name="password" type="password" autocomplete="new-password" minlength="8" required><button type="submit">Reset password</button></form>`);
}

export class AuthController {
    static async register(req: Request, res: Response): Promise<void> {
        try {
            const { email, username, password } = req.body;

            const normalizedEmail = typeof email === 'string' ? email.trim().toLowerCase() : '';
            const normalizedUsername = typeof username === 'string' ? username.trim() : '';

            if (!isValidEmail(normalizedEmail)) {
                res.status(400).json({ error: 'Invalid email format.' });
                return;
            }

            const passwordCheck = validatePasswordStrength(password);
            if (!passwordCheck.isValid) {
                res.status(400).json({ error: 'Password does not meet strength requirements.', details: passwordCheck.errors });
                return;
            }

            // Check if email or username already exists (provides strict visual feedback)
            const existingUser = await UserRepository.findByEmailOrUsername(
                normalizedEmail,
                normalizedUsername,
            );
            if (existingUser) {
                if (existingUser.email.toLowerCase() === normalizedEmail) {
                    res.status(409).json({ error: 'Email is already in use.', field: 'email' });
                    return;
                }
                if (existingUser.username === normalizedUsername) {
                    res.status(409).json({ error: 'Username is already in use.', field: 'username' });
                    return;
                }
            }

            const salt = await bcrypt.genSalt(BCRYPT_SALT_ROUNDS);
            const passwordHash = await bcrypt.hash(password, salt);
            const verification = createVerificationToken();

            const newUser = await UserRepository.createUser(
                normalizedEmail,
                normalizedUsername,
                passwordHash,
                verification.tokenHash,
                verification.expiresAt,
            );

            let verificationEmailSent = true;
            try {
                await sendVerificationEmail({
                    to: newUser.email,
                    username: newUser.username,
                    token: verification.rawToken,
                });
            } catch (emailError) {
                verificationEmailSent = false;
                console.error('Failed to send verification email:', emailError);
            }

            res.status(201).json({
                message: verificationEmailSent
                    ? 'Account created successfully. Please verify your email.'
                    : 'Account created, but the verification email could not be sent. Please request a new one.',
                verificationEmailSent,
                user: { id: newUser.id, email: newUser.email, username: newUser.username },
            });
        } catch (error) {
            res.status(500).json({ error: 'Internal server error during registration.' });
        }
    }

    static async login(req: Request, res: Response): Promise<void> {
        try {
            const { email, password } = req.body;
            const normalizedEmail = typeof email === 'string' ? email.trim().toLowerCase() : '';
            const user = await UserRepository.findByEmailOrUsername(normalizedEmail, '');
            if (!user) {
                res.status(404).json({
                    error: 'No account is registered with this email.',
                    code: 'ACCOUNT_NOT_FOUND',
                });
                return;
            }

            const isMatch = await bcrypt.compare(password, user.password_hash);
            if (!isMatch) {
                res.status(401).json({ error: 'Invalid email or password.' });
                return;
            }

            if (!user.is_verified) {
                res.status(403).json({
                    error: 'Please verify your email before logging in.',
                    code: 'EMAIL_NOT_VERIFIED',
                });
                return;
            }

            const token = jwt.sign({ userId: user.id, email: user.email }, JWT_SECRET, { expiresIn: '7d' });

            res.status(200).json({ message: 'Login successful', token, user: { id: user.id, email: user.email, username: user.username } });
        } catch (error) {
            res.status(500).json({ error: 'Internal server error during login.' });
        }
    }

    static async verifyEmail(req: Request, res: Response): Promise<void> {
        const rawToken = typeof req.query.token === 'string' ? req.query.token : '';
        if (!rawToken) {
            res.status(400).send(verificationPage(
                'Invalid verification link',
                'The verification token is missing.',
                false,
            ));
            return;
        }

        try {
            const tokenHash = createHash('sha256').update(rawToken).digest('hex');
            const user = await UserRepository.verifyEmail(tokenHash);
            if (!user) {
                res.status(400).send(verificationPage(
                    'Link invalid or expired',
                    'Request a new verification email and try again.',
                    false,
                ));
                return;
            }

            res.status(200).send(verificationPage(
                'Email verified',
                'Your account has been verified successfully.',
                true,
            ));
        } catch (error) {
            console.error('Email verification failed:', error);
            res.status(500).send(verificationPage(
                'Verification failed',
                'Something went wrong. Please try again later.',
                false,
            ));
        }
    }

    static async resendVerificationEmail(req: Request, res: Response): Promise<void> {
        try {
            const email = typeof req.body.email === 'string'
                ? req.body.email.trim().toLowerCase()
                : '';
            const genericMessage = 'If an unverified account exists, a verification email has been sent.';

            if (!isValidEmail(email)) {
                res.status(400).json({ error: 'Invalid email format.' });
                return;
            }

            const user = await UserRepository.findByEmailOrUsername(email, '');
            if (!user || user.is_verified) {
                res.status(200).json({ message: genericMessage });
                return;
            }

            const verification = createVerificationToken();
            await UserRepository.setVerificationToken(
                user.id,
                verification.tokenHash,
                verification.expiresAt,
            );
            await sendVerificationEmail({
                to: user.email,
                username: user.username,
                token: verification.rawToken,
            });

            res.status(200).json({ message: genericMessage });
        } catch (error) {
            console.error('Resending verification email failed:', error);
            res.status(502).json({ error: 'Unable to send verification email right now.' });
        }
    }

    static async requestPasswordReset(req: Request, res: Response): Promise<void> {
        // Always respond with the same generic message, regardless of whether the
        // email exists, so this endpoint can't be used to enumerate accounts.
        const genericMessage = 'If an account with that email exists, a password reset link has been sent.';

        try {
            const email = typeof req.body.email === 'string'
                ? req.body.email.trim().toLowerCase()
                : '';

            if (!isValidEmail(email)) {
                res.status(400).json({ error: 'Invalid email format.' });
                return;
            }

            const user = await UserRepository.findByEmailOrUsername(email, '');
            if (user) {
                const reset = createResetToken();
                await UserRepository.setResetToken(user.id, reset.tokenHash, reset.expiresAt);
                try {
                    await sendPasswordResetEmail({
                        to: user.email,
                        username: user.username,
                        token: reset.rawToken,
                    });
                } catch (emailError) {
                    console.error('Failed to send password reset email:', emailError);
                }
            }

            res.status(200).json({ message: genericMessage });
        } catch (error) {
            console.error('Password reset request failed:', error);
            res.status(500).json({ error: 'Unable to process password reset request right now.' });
        }
    }

    static async resetPassword(req: Request, res: Response): Promise<void> {
        // The reset link from the email opens this in a browser (GET), which shows
        // a simple HTML form; the form then submits back here (POST) to actually
        // change the password. The mobile app can instead call this directly with
        // JSON, in which case we respond with JSON instead of rendering HTML.
        if (req.method === 'GET') {
            const rawToken = typeof req.query.token === 'string' ? req.query.token : '';
            if (!rawToken) {
                res.status(400).send(resetPasswordPage('', 'This reset link is missing its token.'));
                return;
            }
            res.status(200).send(resetPasswordPage(rawToken));
            return;
        }

        const rawToken = typeof req.body?.token === 'string'
            ? req.body.token
            : (typeof req.query.token === 'string' ? req.query.token : '');
        const newPassword = typeof req.body?.password === 'string' ? req.body.password : '';
        const isBrowserForm = Boolean(req.is('application/x-www-form-urlencoded'));

        try {
            if (!rawToken) {
                throw new Error('This reset link is invalid or has expired.');
            }

            const passwordCheck = validatePasswordStrength(newPassword);
            if (!passwordCheck.isValid) {
                throw new Error(passwordCheck.errors.join(' '));
            }

            const tokenHash = createHash('sha256').update(rawToken).digest('hex');
            const salt = await bcrypt.genSalt(BCRYPT_SALT_ROUNDS);
            const passwordHash = await bcrypt.hash(newPassword, salt);

            const user = await UserRepository.resetPassword(tokenHash, passwordHash);
            if (!user) {
                throw new Error('This reset link is invalid or has expired.');
            }

            if (isBrowserForm) {
                res.status(200).send(verificationPage(
                    'Password updated',
                    'Your password has been changed successfully.',
                    true,
                ));
                return;
            }
            res.status(200).json({ message: 'Password updated successfully.' });
        } catch (error) {
            const message = error instanceof Error ? error.message : 'Unable to reset password.';
            if (isBrowserForm) {
                res.status(400).send(resetPasswordPage(rawToken, message));
                return;
            }
            res.status(400).json({ error: message });
        }
    }
}