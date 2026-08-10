import { Router } from 'express';
import { InviteController } from '../controllers/invite.controller';
import { verifyToken } from '../middleware/auth.middleware';

const router = Router();

router.post('/send', verifyToken, InviteController.sendInvite);
router.get('/pending', verifyToken, InviteController.getPendingInvites);
router.post('/respond', verifyToken, InviteController.respondToInvite);

export default router;