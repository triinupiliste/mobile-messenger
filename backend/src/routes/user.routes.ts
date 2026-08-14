import { Router } from 'express';
import { UserController } from '../controllers/user.controller';
import { verifyToken } from '../middleware/auth.middleware';

const router = Router();

router.get('/profile', verifyToken, UserController.getProfile);
router.put('/profile', verifyToken, UserController.updateProfile);
router.get('/search', verifyToken, UserController.searchUsers);
// Must be registered after the more specific routes above, since Express
// matches routes in registration order and this is a wildcard segment.
router.get('/:userId', verifyToken, UserController.getUserById);

export default router;