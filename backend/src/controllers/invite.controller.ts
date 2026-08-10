import { Request, Response } from 'express';
import { InviteRepository } from '../repositories/invite.repository';
import { ChatRepository } from '../repositories/chat.repository';

export class InviteController {
    static async sendInvite(req: Request, res: Response): Promise<void> {
        try {
            const senderId = (req as any).user.userId;
            const { receiverId } = req.body;

            if (senderId === receiverId) {
                res.status(400).json({ error: 'You cannot invite yourself.' });
                return;
            }

            const existing = await InviteRepository.findExistingInvite(senderId, receiverId);
            if (existing) {
                res.status(409).json({ error: 'An invite or relationship already exists between these users.' });
                return;
            }

            const invite = await InviteRepository.createInvite(senderId, receiverId);
            res.status(201).json({ message: 'Chat invite sent successfully.', invite });
        } catch (error) {
            res.status(500).json({ error: 'Failed to send chat invite.' });
        }
    }

    static async getPendingInvites(req: Request, res: Response): Promise<void> {
        try {
            const userId = (req as any).user.userId;
            const invites = await InviteRepository.getPendingInvitesForUser(userId);
            res.status(200).json(invites);
        } catch (error) {
            res.status(500).json({ error: 'Failed to fetch pending invites.' });
        }
    }

    static async respondToInvite(req: Request, res: Response): Promise<void> {
        try {
            const userId = (req as any).user.userId;
            const { inviteId, status } = req.body; // status: 'accepted' or 'declined'

            if (!['accepted', 'declined'].includes(status)) {
                res.status(400).json({ error: 'Invalid response status.' });
                return;
            }

            const invite = await InviteRepository.findById(inviteId);
            if (!invite || invite.receiver_id !== userId) {
                res.status(404).json({ error: 'Invite not found.' });
                return;
            }

            const updated = await InviteRepository.updateInviteStatus(inviteId, status);

            // If accepted, automatically create a chat channel between sender and receiver
            if (status === 'accepted') {
                await ChatRepository.createChatBetweenUsers(invite.sender_id, invite.receiver_id);
            }

            res.status(200).json({ message: `Invite ${status} successfully.`, invite: updated });
        } catch (error) {
            res.status(500).json({ error: 'Failed to respond to invite.' });
        }
    }
}