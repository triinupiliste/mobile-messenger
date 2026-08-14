# Mobile Messenger

## Introduction

Mobile Messenger is a real-time, end-to-end chat application. Its Flutter Android client connects to a Node.js, Express, Socket.IO, and PostgreSQL backend running in Docker.

Users can create accounts, verify their email addresses, search for and invite contacts, exchange text/image/video/audio messages, and get push notifications for new messages and invitations. The backend is authoritative: it persists every message, encrypts sensitive data at rest, and pushes real-time updates to connected clients through Socket.IO.

## Main Features

- Email/password registration, verification, password reset, and persisted sessions
- Contact search by username or email, with sendable/acceptable/declinable invitations and a pending-invites view
- Profile page with editable username, About Me, and profile picture
- Text, image, video, and audio (voice note) messaging
- Real-time typing indicators and sent/delivered/read status
- Message editing and deletion
- Chat list sorted by most recent activity, with archive/unarchive support
- Push notifications for new messages and invitations, with per-chat mute
- AES-256 encryption of message content, profile fields, and media files at rest

## Technology Stack

| Area | Technology |
| --- | --- |
| Mobile client | Flutter / Dart, Provider, `http`, `socket_io_client` |
| Backend | Node.js, Express, TypeScript, Socket.IO |
| Database | PostgreSQL 15, run via Docker Compose |
| Authentication | JWT and bcrypt password hashing |
| Data protection | AES-256-CBC encryption of message content, profile fields, and media files at rest |
| Email | Brevo Email API for verification and password-reset messages |
| Push notifications | Firebase Cloud Messaging (FCM) with `flutter_local_notifications` |
| Media | `image_picker`, `record`, `audioplayers` for photo, video, and voice messages |

## Quick Start Guide for Reviewers

There is no hosted backend or prebuilt APK for this project — the backend must be started locally with Docker, and the Flutter client is run against it. See [Developer Setup](#developer-setup) below for the full walkthrough.

In short:

```bash
docker compose up --build
```

```bash
cd frontend
flutter pub get
flutter run
```

> The Flutter app reads the backend URL from [frontend/lib/config/server_config.dart](frontend/lib/config/server_config.dart). Update `serverBaseUrl` there to point at your backend (`http://127.0.0.1:5000` with `adb reverse`, or an ngrok HTTPS URL for a physical device on a separate network).

## How to Use the App

### First Sign-In

1. Register with a unique username, an email address that can receive email, and a password containing at least eight characters with uppercase, lowercase, numeric, and special characters.
2. Open the verification email and verify the account.
3. Sign in. Use **Forgot Password** if needed.

### Add a Contact and Start Chatting

1. Register and verify two accounts (two devices, or a device plus an emulator).
2. From the search screen, look up the other account by username or email and send an invitation.
3. Accept the invitation from the **Incoming** tab on the other account.
4. Open the new chat and send text, image, video, or audio messages. Both devices update in real time via Socket.IO.

### Manage Chats and Notifications

- Archive or unarchive a chat from the chat list.
- Mute or unmute notifications for an individual chat from its menu.
- Edit or delete your own messages from the chat room.

### Reviewer Guide

| Area | Quick check |
| --- | --- |
| Authentication | Register, verify the email, reset password, sign in, and sign out. |
| Profile | Edit username/About Me and upload a profile picture. |
| Contacts & invites | Search for a user, send an invitation, and accept/decline it from the other account. |
| Messaging | Send text, image, video, and audio messages; confirm typing indicators and read receipts. |
| Chat list | Confirm chats sort by most recent message, and archive/unarchive works. |
| Push notifications | Background the app, receive a message from another account, and confirm a push notification arrives (and is suppressed when the chat is muted). |

## Developer Setup

### Prerequisites

- Git
- Node.js 18+ and npm
- Docker with Docker Compose
- Flutter SDK and Android build tooling
- An ngrok account/client when testing from a physical device outside the local network
- A Brevo account with an API key and verified sender if email verification and password reset should work
- A Firebase project with an Android app configured, if push notifications should work

### Clone and Install

```bash
git clone https://gitea.kood.tech/triinupiliste/mobile-messenger.git
cd mobile-messenger
cd backend && npm install
cd ../frontend && flutter pub get
```

### Configure the Backend

Copy [.env.example](.env.example) to `.env` at the repository root. This local file is ignored by Git and must never be committed.

```env
APP_BASE_URL=http://localhost:5000/api

BREVO_API_KEY=replace_with_your_brevo_api_key
MAIL_FROM=verified-sender@example.com
MAIL_FROM_NAME=Mobile Messenger
```

`docker-compose.yml` supplies the remaining backend configuration (`DB_*`, `JWT_SECRET`, `ENCRYPTION_KEY`) as environment variables for local use. Replace `JWT_SECRET` and `ENCRYPTION_KEY` with your own strong values before any real deployment.

To enable outgoing emails, set a Brevo **API key** and a verified sender address in `.env`. The backend uses Brevo's HTTPS Email API, not SMTP.

To enable push notifications, place a Firebase service account key at `backend/secrets/firebase-service-account.json` and a matching `google-services.json` at `frontend/android/app/google-services.json`. Both are Firebase project downloads and are not committed to the repository.

Keep `ENCRYPTION_KEY` stable after users have registered: changing it makes existing encrypted messages, profile data, and media unreadable. Never commit `BREVO_API_KEY`, database passwords, signing keys, or Firebase credentials.

### Run the Local App

Run these commands in order:

1. Start PostgreSQL and the backend together:

   ```bash
   docker compose up --build
   ```

2. Confirm the backend is up (look for `🚀 Backend server running on port 5000` in the logs, or check that it responds instead of connection-refused):

   ```bash
   curl -i http://localhost:5000/api/auth/login
   ```

3. Point the Flutter client at the backend by editing `serverBaseUrl` in [frontend/lib/config/server_config.dart](frontend/lib/config/server_config.dart):
   - Single USB-tethered device with `adb reverse tcp:5000 tcp:5000`: `http://127.0.0.1:5000`
   - Physical device(s) on a separate network, backend exposed via ngrok:

     ```bash
     ngrok http 5000
     ```

     then use the printed HTTPS `ngrok-free.app` address.

4. Run the app:

   ```bash
   cd frontend
   flutter run
   ```

For an emulator or phone on the same Wi-Fi network, ngrok is optional — use `http://<computer-LAN-IP>:5000` instead. Do not use `localhost` when the client runs on a separate device.

## Code Organisation

```text
mobile-messenger/
├── docker-compose.yml    # Postgres + backend, single-command local stack
├── backend/
│   ├── database/         # init.sql (auto-applied) and versioned migrations
│   ├── secrets/          # Firebase service account (not committed)
│   └── src/
│       ├── config/       # Database pool configuration
│       ├── controllers/  # HTTP request handlers
│       ├── middleware/   # Auth, upload, and error-handling middleware
│       ├── models/       # Backend domain models
│       ├── repositories/ # PostgreSQL queries and persistence
│       ├── routes/       # Express route definitions
│       ├── services/     # Email and push-notification services
│       ├── sockets/      # Socket.IO event handlers
│       ├── utils/        # Encryption and validation helpers
│       └── server.ts     # HTTP and Socket.IO server entry point
└── frontend/
    └── lib/
        ├── config/       # Backend URL configuration
        ├── constants/    # Shared app constants
        ├── models/       # App data models
        ├── providers/    # Client application state
        ├── screens/      # Auth, profile, chat, and invite UI
        ├── services/     # REST, socket, storage, and push-notification clients
        ├── theme/        # Shared colours and theme setup
        ├── widgets/       # Reusable UI components
        └── main.dart     # Flutter application entry point
```

## Implementation Details

- **Encryption at rest:** message content, profile fields (About Me, avatar URL), and media file bytes are AES-256-CBC encrypted before being written to the database or disk, and decrypted on the fly when served.
- **Real-time synchronisation:** Socket.IO broadcasts new messages, typing status, read receipts, edits, and deletions to each chat's participants.
- **Push notifications:** Firebase Cloud Messaging delivers background notifications for new messages and invitations; notifications respect a per-chat mute setting.
- **Authoritative uploads:** media uploads are stored server-side with generated filenames and served through an authenticated, path-traversal-guarded endpoint rather than static file serving.
- **Privacy:** passwords are bcrypt hashes; JWTs authenticate both REST and Socket.IO connections.

## Troubleshooting

- **Local backend cannot connect to PostgreSQL:** run `docker compose up --build`, confirm port `5432` is free, and check the `postgres` service logs.
- **Verification email is missing:** check spam, ensure the sender is verified in Brevo, and confirm `BREVO_API_KEY` and `MAIL_FROM` are set in `.env`.
- **Phone cannot reach the local backend:** keep the backend and ngrok tunnel running, then update `serverBaseUrl` in `server_config.dart` with the current ngrok HTTPS address — free ngrok URLs change between sessions.
- **Push notifications don't arrive:** confirm `backend/secrets/firebase-service-account.json` and `frontend/android/app/google-services.json` are both present and match the same Firebase project.
- **Port 5000 or 5432 is occupied:** stop the process already using it, or change the port mapping in `docker-compose.yml`.
- **Existing data unreadable after a configuration change:** restore the original `ENCRYPTION_KEY`; encrypted messages, profile fields, and media depend on that stable key.
