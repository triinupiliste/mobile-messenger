import express from 'express';
import http from 'http';
import { Server } from 'socket.io';
import cors from 'cors';
import dotenv from 'dotenv';

import authRoutes from './routes/auth.routes';
import userRoutes from './routes/user.routes';
import inviteRoutes from './routes/invite.routes';
import chatRoutes from './routes/chat.routes';
import { errorHandler } from './middleware/error.middleware';
import { registerChatHandlers } from './sockets/chat.socket';

dotenv.config();

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
    cors: {
        origin: '*', // Adjust for production security later
        methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE']
    }
});

// Middleware
app.use(cors());
app.use(express.json());

// API Routes
app.use('/api/auth', authRoutes);
app.use('/api/users', userRoutes);
app.use('/api/invites', inviteRoutes);
app.use('/api/chats', chatRoutes);

// Global Error Handler
app.use(errorHandler);

// Register Socket.io Event Handlers
registerChatHandlers(io);

const PORT = process.env.PORT || 5000;
server.listen(PORT, () => {
    console.log(`🚀 Backend server running on port ${PORT}`);
});

export default server;