my-messenger-app/
├── docker-compose.yml         # Starts both PostgreSQL and backend container with 1 command
└── backend/                   # All backend source code & configuration
    ├── Dockerfile             # Builds the Node.js/TypeScript image
    ├── package.json           # Dependencies (express, pg, socket.io, bcrypt, etc.)
    ├── tsconfig.json          # TypeScript compilation settings
    ├── database/              
    │   └── init.sql           # Your PostgreSQL schema script
    └── src/
        ├── server.ts          # Main application entry point (Express + Socket.io server)
        ├── config/
        │   └── database.ts    # PostgreSQL connection pool configuration
        ├── models/            <-- ADDED THIS FOLDER
        │   ├── user.model.ts      # TypeScript interfaces for User & Profile data
        │   ├── chat.model.ts      # TypeScript interfaces for Chats & Participants
        │   ├── message.model.ts   # TypeScript interfaces for Messages
        │   └── invite.model.ts    # TypeScript interfaces for Chat Invites
        ├── middleware/
        │   ├── auth.middleware.ts   # JWT verification middleware for protected routes
        │   └── error.middleware.ts  # Global error handler (ensures stable error responses)
        ├── controllers/
        │   ├── auth.controller.ts   # Registration, login, password recovery, verification logic
        │   ├── user.controller.ts   # Profile management, search, and data updates
        │   ├── invite.controller.ts # Sending, accepting, declining, and listing chat invites
        │   └── chat.controller.ts   # Fetching chat lists, archiving, and message history
        ├── routes/
        │   ├── auth.routes.ts       # Express routes for authentication
        │   ├── user.routes.ts       # Express routes for user profiles and searches
        │   ├── invite.routes.ts     # Express routes for chat invitations
        │   └── chat.routes.ts       # Express routes for chats and message retrieval
        ├── sockets/
        │   └── chat.socket.ts       # Real-time messaging, typing indicators, and delivery receipts
        └── utils/
            ├── encryption.util.ts   # AES encryption/decryption helpers for sensitive data
            └── validator.util.ts    # Password strength regex checks & input validators