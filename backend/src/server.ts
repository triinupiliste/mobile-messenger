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
import { runMigrations } from './config/migrate';
import { ALLOWED_ORIGINS } from './config/env';

dotenv.config();

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
    cors: {
        origin: ALLOWED_ORIGINS,
        methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE']
    }
});
setIO(io);


// Middleware
app.use(cors({ origin: ALLOWED_ORIGINS }));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Serve uploaded media (images, videos, voice notes). Files are stored encrypted
// at rest, so this decrypts them on the fly rather than using express.static.
// Requires a valid JWT (header or ?token= query param) so media can't be
// fetched by anyone who merely guesses/observes a filename.
app.get('/uploads/:filename', verifyMediaToken, MediaController.getMedia);

// Root health-check route before your API routes
app.get('/', (req, res) => {
    res.status(200).json({ status: 'ok', message: 'Mobile Messenger API is running' });
});

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

// Ensure the schema exists before accepting any requests — critical for a
// fresh deploy against a managed Postgres host (e.g. Railway) that has no
// existing tables yet.
runMigrations()
    .catch((err) => {
        console.error('Failed to run database migrations:', err);
        process.exit(1);
    })
    .then(() => {
        server.listen(Number(PORT), '0.0.0.0', () => {
            console.log(`Backend server running on port ${PORT}`);
        });
    });

export default server;