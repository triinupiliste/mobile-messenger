import { Router } from 'express';
import { ChatController } from '../controllers/chat.controller';
import { verifyToken } from '../middleware/auth.middleware';

const router = Router();

router.get('/', verifyToken, ChatController.getChatList);
router.patch('/:chatId/archive', verifyToken, ChatController.toggleArchiveChat);
router.get('/:chatId/messages', verifyToken, ChatController.getChatMessages);
router.patch('/:chatId/read', verifyToken, ChatController.markMessagesRead);

export default router;