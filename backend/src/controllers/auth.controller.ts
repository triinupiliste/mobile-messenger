import { Request, Response } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { createHash, randomBytes } from 'crypto';
import { UserRepository } from '../repositories/user.repository';
import { validatePasswordStrength, isValidEmail } from '../utils/validator.util';
import { sendVerificationEmail } from '../services/email.service';

const VERIFICATION_TOKEN_LIFETIME_MS = 24 * 60 * 60 * 1000;

function createVerificationToken(): { rawToken: string; tokenHash: string; expiresAt: Date } {
    const rawToken = randomBytes(32).toString('hex');
    return {
        rawToken,
        tokenHash: createHash('sha256').update(rawToken).digest('hex'),
        expiresAt: new Date(Date.now() + VERIFICATION_TOKEN_LIFETIME_MS),
    };
}

function verificationPage(title: string, message: string, successful: boolean): string {
    const color = successful ? '#16a34a' : '#dc2626';
    return `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title></head><body style="font-family:Arial,sans-serif;background:#fff5f2;padding:32px"><main style="max-width:520px;margin:auto;background:white;padding:32px;border-radius:16px;text-align:center"><h1 style="color:${color}">${title}</h1><p>${message}</p><p>You may now return to Mobile Messenger.</p></main></body></html>`;
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

            // Check if email or username already exists (provides strict visual feedback requirement)
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

            const salt = await bcrypt.genSalt(10);
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

            const token = jwt.sign({ userId: user.id, email: user.email }, process.env.JWT_SECRET || 'fallback_secret', { expiresIn: '7d' });

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
}