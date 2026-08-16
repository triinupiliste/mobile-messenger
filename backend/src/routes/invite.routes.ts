import { Router } from 'express';
import { InviteController } from '../controllers/invite.controller';
import { verifyToken } from '../middleware/auth.middleware';

const router = Router();

// All invite routes require authentication
router.post('/', verifyToken, InviteController.sendInvite); // POST /api/invites
router.get('/', verifyToken, InviteController.getPendingInvites); // GET /api/invites
router.post('/respond', verifyToken, InviteController.respondToInvite); // POST /api/invites/respond

export default router;