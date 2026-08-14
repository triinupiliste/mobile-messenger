import { Router } from 'express';
import { MediaController } from '../controllers/media.controller';
import { verifyToken } from '../middleware/auth.middleware';
import { uploadMedia, uploadAvatar } from '../middleware/upload.middleware';

const router = Router();

router.post('/upload', verifyToken, uploadMedia.single('file'), MediaController.uploadMedia);
router.post('/avatar', verifyToken, uploadAvatar, MediaController.uploadMedia);

export default router;
