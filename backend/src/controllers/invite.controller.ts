import { Request, Response } from 'express';
import { InviteRepository } from '../repositories/invite.repository';
import { ChatRepository } from '../repositories/chat.repository';
import { UserRepository } from '../repositories/user.repository';
import { PushService } from '../services/push.service';
import { getIO } from '../sockets/socket.instance';
import { logger } from '../utils/logger.util';

export class InviteController {
    static async sendInvite(req: Request, res: Response): Promise<void> {
        try {
            const senderId = req.user!.userId;
            const { receiverId } = req.body;

            if (typeof receiverId !== 'string' || !receiverId.trim()) {
                res.status(400).json({ error: 'A valid receiverId is required.' });
                return;
            }

            if (senderId === receiverId) {
                res.status(400).json({ error: 'You cannot invite yourself.' });
                return;
            }

            if (!await UserRepository.existsById(receiverId)) {
                res.status(404).json({ error: 'The selected user no longer exists.' });
                return;
            }

            const existing = await InviteRepository.findExistingInvite(senderId, receiverId);
            if (existing) {
                res.status(409).json({ error: 'An invite or relationship already exists between these users.' });
                return;
            }

            const invite = await InviteRepository.createInvite(senderId, receiverId);
            res.status(201).json({ message: 'Chat invite sent successfully.', invite });

            // Let the receiver's Invites screen update live; emit the enriched shape
            // (with sender username/avatar) that the screen expects.
            const enrichedInvite = await InviteRepository.getIncomingInviteById(invite.id);
            getIO()?.to(receiverId).emit('new_invite', enrichedInvite ?? invite);

            // Push-notify the receiver — failures here must not affect the response above.
            try {
                const [sender, receiver] = await Promise.all([
                    UserRepository.getPushInfoById(senderId),
                    UserRepository.getPushInfoById(receiverId),
                ]);
                if (receiver?.fcm_token) {
                    await PushService.sendToToken(receiver.fcm_token, {
                        title: 'New chat invite',
                        body: `${sender?.username || 'Someone'} has sent you an invite`,
                        data: { type: 'invite' },
                    });
                }
            } catch (pushError) {
                logger.error('Failed to send invite push notification:', pushError);
            }
        } catch (error) {
            res.status(500).json({ error: 'Failed to send chat invite.' });
        }
    }

    static async getPendingInvites(req: Request, res: Response): Promise<void> {
        try {
            const userId = req.user!.userId;
            const [incoming, outgoing] = await Promise.all([
                InviteRepository.getPendingInvitesForUser(userId),
                InviteRepository.getOutgoingInvitesForUser(userId),
            ]);
            res.status(200).json({ incoming, outgoing });
        } catch (error) {
            res.status(500).json({ error: 'Failed to fetch pending invites.' });
        }
    }

    static async respondToInvite(req: Request, res: Response): Promise<void> {
        try {
            const userId = req.user!.userId;
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

            // If accepted, create a new chat — or revive the old one (with history)
            // if they'd previously unfriended each other.
            if (status === 'accepted') {
                const existingChatId = await ChatRepository.findChatBetweenUsers(invite.sender_id, invite.receiver_id);
                if (existingChatId) {
                    await ChatRepository.reviveForAllParticipants(existingChatId);
                } else {
                    await ChatRepository.createChatBetweenUsers(invite.sender_id, invite.receiver_id);
                }
            }

            // Let the sender's Invites/Search screens update live if they're open.
            getIO()?.to(invite.sender_id).emit('invite_responded', updated);

            res.status(200).json({ message: `Invite ${status} successfully.`, invite: updated });
        } catch (error) {
            res.status(500).json({ error: 'Failed to respond to invite.' });
        }
    }
}