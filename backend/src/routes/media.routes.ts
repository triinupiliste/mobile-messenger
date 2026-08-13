import { Router } from 'express';
import { MediaController } from '../controllers/media.controller';
import { verifyToken } from '../middleware/auth.middleware';
import { uploadMedia } from '../middleware/upload.middleware';

const router = Router();

router.post('/upload', verifyToken, uploadMedia.single('file'), MediaController.uploadMedia);

export default router;
