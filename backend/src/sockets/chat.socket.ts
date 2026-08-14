import { Server, Socket } from 'socket.io';
import jwt from 'jsonwebtoken';
import { MessageRepository } from '../repositories/message.repository';
import { ChatRepository } from '../repositories/chat.repository';
import { UserRepository } from '../repositories/user.repository';
import { PushService } from '../services/push.service';

function buildMessagePreview(content: string | null | undefined, mediaType: string): string {
    switch (mediaType) {
        case 'image':
            return 'Sent a photo';
        case 'video':
            return 'Sent a video';
        case 'audio':
            return 'Sent a voice message';
        default: {
            // One-line preview — the OS notification will further truncate/ellipsize
            // to whatever fits on screen, so we just strip newlines here.
            const flat = (content || '').replace(/\s+/g, ' ').trim();
            return flat || 'Sent a message';
        }
    }
}

export function registerChatHandlers(io: Server) {
    // 1. Socket Authentication Middleware with explicit 'next' type
    io.use((socket: Socket, next: (err?: any) => void) => { // <-- Added explicit type here
        const token = socket.handshake.auth.token || socket.handshake.headers['authorization']?.split(' ')[1];
        
        if (!token) {
            return next(new Error('Authentication error: Token missing'));
        }

        jwt.verify(token, process.env.JWT_SECRET || 'fallback_secret', (err: any, decoded: any) => {
            if (err) {
                return next(new Error('Authentication error: Invalid or expired token'));
            }
            socket.data.user = decoded; 
            next();
        });
    });

    // 2. Connection Event Listener
    io.on('connection', (socket: Socket) => {
        const userId = socket.data.user.userId;
        console.log(`🔌 User connected via WebSocket: ${userId}`);

        // Join a personal room for direct notifications (e.g., invites)
        socket.join(userId);

        // Join a specific chat room
        socket.on('join_chat', (chatId: string) => {
            socket.join(chatId);
            console.log(`User ${userId} joined chat room: ${chatId}`);
        });

        // Handle sending messages (Text, Images, Videos, Audio)
        socket.on('send_message', async (data: { chatId: string; content?: string; mediaUrl?: string; mediaType?: any }) => {
            try {
                const { chatId, content, mediaUrl, mediaType } = data;
                
                // Save message to database and encrypt content
                const savedMessage = await MessageRepository.saveMessage(
                    chatId, 
                    userId, 
                    content, 
                    mediaUrl, 
                    mediaType || 'text'
                );
                
                // Broadcast the message to all participants in the chat room
                io.to(chatId).emit('receive_message', savedMessage);

                // Push-notify every other participant who isn't muted on this chat.
                try {
                    const [sender, otherParticipants] = await Promise.all([
                        UserRepository.getPushInfoById(userId),
                        ChatRepository.getOtherParticipantsForPush(chatId, userId),
                    ]);
                    const senderName = sender?.username || 'Someone';
                    const previewBody = buildMessagePreview(savedMessage.content, savedMessage.media_type);

                    for (const participant of otherParticipants) {
                        if (participant.is_muted || !participant.fcm_token) continue;
                        await PushService.sendToToken(participant.fcm_token, {
                            title: senderName,
                            body: previewBody,
                            data: {
                                type: 'message',
                                chatId,
                                contactId: userId,
                                contactName: senderName,
                            },
                        });
                    }
                } catch (pushError) {
                    console.error('Failed to send message push notification:', pushError);
                }
            } catch (error) {
                socket.emit('error_feedback', { message: 'Failed to send message.' });
            }
        });

        // Handle Typing Indicators (Real-time typing cues)
        socket.on('typing', (data: { chatId: string; isTyping: boolean }) => {
            socket.to(data.chatId).emit('user_typing', { chatId: data.chatId, userId, isTyping: data.isTyping });
        });

        // Handle Message Status Updates (Delivered / Read indicators)
        socket.on('update_message_status', async (data: { messageId: string; chatId: string; status: 'delivered' | 'read' }) => {
            try {
                await MessageRepository.updateMessageStatus(data.messageId, data.status);
                io.to(data.chatId).emit('message_status_updated', { messageId: data.messageId, status: data.status });
            } catch (error) {
                console.error('Failed to update message status:', error);
            }
        });

        // Handle Editing Messages
        socket.on('edit_message', async (data: { messageId: string; chatId: string; newContent: string }) => {
            try {
                const updatedMessage = await MessageRepository.editMessage(data.messageId, userId, data.newContent);
                if (updatedMessage) {
                    io.to(data.chatId).emit('message_edited', updatedMessage);
                } else {
                    socket.emit('error_feedback', { message: 'Could not edit this message.' });
                }
            } catch (error) {
                socket.emit('error_feedback', { message: 'Failed to edit message.' });
            }
        });

        // Handle Deleting Messages
        socket.on('delete_message', async (data: { messageId: string; chatId: string }) => {
            try {
                const deletedMessage = await MessageRepository.deleteMessage(data.messageId, userId);
                if (deletedMessage) {
                    io.to(data.chatId).emit('message_deleted', deletedMessage);
                } else {
                    socket.emit('error_feedback', { message: 'Could not delete this message.' });
                }
            } catch (error) {
                socket.emit('error_feedback', { message: 'Failed to delete message.' });
            }
        });

        // Disconnection handler
        socket.on('disconnect', () => {
            console.log(`🔌 User disconnected: ${userId}`);
        });
    });
}