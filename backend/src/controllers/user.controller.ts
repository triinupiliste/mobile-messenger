import { Request, Response } from 'express';
import { UserRepository } from '../repositories/user.repository';

export class UserController {
    static async getProfile(req: Request, res: Response): Promise<void> {
        try {
            const userId = (req as any).user.userId;
            const profile = await UserRepository.getProfile(userId);
            if (!profile) {
                res.status(404).json({ error: 'Profile not found.' });
                return;
            }
            res.status(200).json(profile);
        } catch (error) {
            res.status(500).json({ error: 'Failed to fetch user profile.' });
        }
    }

    static async updateProfile(req: Request, res: Response): Promise<void> {
        try {
            const userId = (req as any).user.userId;
            const { avatar_url, about_me } = req.body;

            const updatedProfile = await UserRepository.updateProfile(userId, avatar_url, about_me);
            res.status(200).json({ message: 'Profile updated successfully', profile: updatedProfile });
        } catch (error) {
            res.status(500).json({ error: 'Failed to update profile.' });
        }
    }

    static async searchUsers(req: Request, res: Response): Promise<void> {
        try {
            const currentUserId = (req as any).user.userId;
            const searchTerm = req.query.q as string;

            if (!searchTerm) {
                res.status(400).json({ error: 'Search query parameter "q" is required.' });
                return;
            }

            const users = await UserRepository.searchUsers(searchTerm, currentUserId);
            res.status(200).json(users);
        } catch (error) {
            res.status(500).json({ error: 'Failed to search users.' });
        }
    }
}