import express from 'express';
import http from 'http';
import { Server } from 'socket.io';
import cors from 'cors';
import dotenv from 'dotenv';

import authRoutes from './routes/auth.routes';
import userRoutes from './routes/user.routes';
import inviteRoutes from './routes/invite.routes';
import chatRoutes from './routes/chat.routes';
import mediaRoutes from './routes/media.routes';
import { MediaController } from './controllers/media.controller';
import { errorHandler } from './middleware/error.middleware';
import { verifyMediaToken } from './middleware/auth.middleware';
import { registerChatHandlers } from './sockets/chat.socket';
import { setIO } from './sockets/socket.instance';

dotenv.config();

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
    cors: {
        origin: '*', // Adjust for production security later
        methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE']
    }
});
setIO(io);


// Middleware
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Serve uploaded media (images, videos, voice notes). Files are stored encrypted
// at rest, so this decrypts them on the fly rather than using express.static.
// Requires a valid JWT (header or ?token= query param) so media can't be
// fetched by anyone who merely guesses/observes a filename.
app.get('/uploads/:filename', verifyMediaToken, MediaController.getMedia);

// API Routes
app.use('/api/auth', authRoutes);
app.use('/api/users', userRoutes);
app.use('/api/invites', inviteRoutes);
app.use('/api/chats', chatRoutes);
app.use('/api/media', mediaRoutes);

// Global Error Handler
app.use(errorHandler);

// Register Socket.io Event Handlers
registerChatHandlers(io);

const PORT = process.env.PORT || 5000;
server.listen(PORT, () => {
    console.log(`🚀 Backend server running on port ${PORT}`);
});

export default server;