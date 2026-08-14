import { Request, Response } from 'express';
import { ChatRepository } from '../repositories/chat.repository';
import { MessageRepository } from '../repositories/message.repository';
import { getIO } from '../sockets/socket.instance';

export class ChatController {
    static async getChatList(req: Request, res: Response): Promise<void> {
        try {
            const userId = (req as any).user.userId;
            const chats = await ChatRepository.getChatListForUser(userId);
            res.status(200).json(chats);
        } catch (error) {
            res.status(500).json({ error: 'Failed to fetch chat list.' });
        }
    }

    static async toggleArchiveChat(req: Request, res: Response): Promise<string | void> {
        try {
            const userId = (req as any).user.userId;
            const chatId = req.params.chatId as string; // <-- Explicitly cast as string
            const { isArchived } = req.body;

            await ChatRepository.setChatArchivedStatus(chatId, userId, isArchived);
            res.status(200).json({ message: `Chat ${isArchived ? 'archived' : 'unarchived'} successfully.` });
        } catch (error) {
            res.status(500).json({ error: 'Failed to update chat archive state.' });
        }
    }

    static async toggleMuteChat(req: Request, res: Response): Promise<string | void> {
        try {
            const userId = (req as any).user.userId;
            const chatId = req.params.chatId as string;
            const { isMuted } = req.body;

            await ChatRepository.setChatMutedStatus(chatId, userId, isMuted);
            res.status(200).json({ message: `Chat ${isMuted ? 'muted' : 'unmuted'} successfully.` });
        } catch (error) {
            res.status(500).json({ error: 'Failed to update chat mute state.' });
        }
    }

    static async getChatMessages(req: Request, res: Response): Promise<string | void> {
        try {
            const chatId = req.params.chatId as string; // <-- Explicitly cast as string
            const messages = await MessageRepository.getMessagesForChat(chatId);
            res.status(200).json(messages);
        } catch (error) {
            res.status(500).json({ error: 'Failed to fetch chat messages.' });
        }
    }

    static async markMessagesRead(req: Request, res: Response): Promise<void> {
        try {
            const userId = (req as any).user.userId;
            const chatId = req.params.chatId as string;
            await MessageRepository.markChatMessagesRead(chatId, userId);

            // Notify the other participant(s) in real time so their sent messages show as read.
            getIO()?.to(chatId).emit('messages_read', { chatId, readerId: userId });

            res.status(200).json({ message: 'Messages marked as read.' });
        } catch (error) {
            res.status(500).json({ error: 'Failed to mark messages as read.' });
        }
    }
}