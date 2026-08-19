import { Router } from 'express';
import { InviteController } from '../controllers/invite.controller';
import { verifyToken } from '../middleware/auth.middleware';

const router = Router();

router.post('/', verifyToken, InviteController.sendInvite);
router.get('/', verifyToken, InviteController.getPendingInvites);
router.post('/respond', verifyToken, InviteController.respondToInvite);

export default router;