import { Request, Response } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { UserRepository } from '../repositories/user.repository';
import { validatePasswordStrength, isValidEmail } from '../utils/validator.util';

export class AuthController {
    static async register(req: Request, res: Response): Promise<void> {
        try {
            const { email, username, password } = req.body;

            if (!isValidEmail(email)) {
                res.status(400).json({ error: 'Invalid email format.' });
                return;
            }

            const passwordCheck = validatePasswordStrength(password);
            if (!passwordCheck.isValid) {
                res.status(400).json({ error: 'Password does not meet strength requirements.', details: passwordCheck.errors });
                return;
            }

            // Check if email or username already exists (provides strict visual feedback requirement)
            const existingUser = await UserRepository.findByEmailOrUsername(email, username);
            if (existingUser) {
                if (existingUser.email === email) {
                    res.status(409).json({ error: 'Email is already in use.', field: 'email' });
                    return;
                }
                if (existingUser.username === username) {
                    res.status(409).json({ error: 'Username is already in use.', field: 'username' });
                    return;
                }
            }

            const salt = await bcrypt.genSalt(10);
            const passwordHash = await bcrypt.hash(password, salt);

            const newUser = await UserRepository.createUser(email, username, passwordHash);

            res.status(201).json({ message: 'Account created successfully. Please verify your email.', userId: newUser.id });
        } catch (error) {
            res.status(500).json({ error: 'Internal server error during registration.' });
        }
    }

    static async login(req: Request, res: Response): Promise<void> {
        try {
            const { email, password } = req.body;
            // Fetch using a helper or raw pool query for email lookup
            const user = await UserRepository.findByEmailOrUsername(email, ''); 
            if (!user) {
                res.status(401).json({ error: 'Invalid email or password.' });
                return;
            }

            const isMatch = await bcrypt.compare(password, user.password_hash);
            if (!isMatch) {
                res.status(401).json({ error: 'Invalid email or password.' });
                return;
            }

            const token = jwt.sign({ userId: user.id, email: user.email }, process.env.JWT_SECRET || 'fallback_secret', { expiresIn: '7d' });

            res.status(200).json({ message: 'Login successful', token, user: { id: user.id, email: user.email, username: user.username } });
        } catch (error) {
            res.status(500).json({ error: 'Internal server error during login.' });
        }
    }
}