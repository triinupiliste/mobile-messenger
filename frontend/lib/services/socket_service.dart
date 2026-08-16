import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../config/server_config.dart';
import '../constants/socket_events.dart';
import 'storage_service.dart';

class SocketService {
  static IO.Socket? _socket;
  // The auth token the current _socket connection was created with, so we can
  // detect a different user logging in on the same app process and force a
  // fresh connection instead of silently keeping the previous user's socket.
  static String? _connectedToken;

  // Non-nullable getter to keep all existing provider and screen calls working seamlessly
  static IO.Socket get socket {
    if (_socket == null) {
      throw Exception('Socket has not been initialized. Call initSocket() first.');
    }
    return _socket!;
  }

  static Future<void> initSocket() async {
    final token = await StorageService.getToken();
    if (token == null) return;

    if (_socket != null && _socket!.connected && _connectedToken == token) return;

    // Either not connected, or connected with a DIFFERENT user's token (e.g.
    // switched accounts on the same device without a full app restart) —
    // tear down the stale connection before creating a fresh one.
    if (_socket != null) {
      _socket!.dispose();
      _socket = null;
    }

    _connectedToken = token;
    _socket = IO.io(serverBaseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'auth': {'token': token},
      'extraHeaders': {'ngrok-skip-browser-warning': 'true'},
    });

    final connected = Completer<void>();

    _socket!.onConnect((_) {
      print('🔌 Connected to Socket.io server');
      if (!connected.isCompleted) connected.complete();
    });

    _socket!.onConnectError((error) {
      print('🔌 Socket connect error: $error');
      if (!connected.isCompleted) connected.complete();
    });

    _socket!.onDisconnect((_) {
      print('🔌 Disconnected from Socket.io server');
    });

    _socket!.connect();

    // Wait for the connection to actually establish (or fail) before returning,
    // so callers can rely on the socket being ready right after initSocket().
    await connected.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {},
    );
  }

  static void joinChat(String chatId) {
    // socket.io-client buffers emits until the connection is established,
    // so we don't need to gate this on `connected` — doing so previously
    // caused join/send calls to be silently dropped during a reconnect race.
    _socket?.emit(SocketEvents.joinChat, chatId);
  }

  static void sendMessage(String chatId, String content, {String? mediaUrl, String mediaType = 'text', String? tempId, String? replyToId}) {
    _socket?.emit(SocketEvents.sendMessage, {
      'chatId': chatId,
      'content': content,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      'tempId': tempId,
      'replyToId': replyToId,
    });
  }

  static void updateMessageStatus(String chatId, String messageId, String status) {
    _socket?.emit(SocketEvents.updateMessageStatus, {
      'chatId': chatId,
      'messageId': messageId,
      'status': status,
    });
  }

  static void sendTypingIndicator(String chatId, bool isTyping) {
    _socket?.emit(SocketEvents.typing, {'chatId': chatId, 'isTyping': isTyping});
  }

  static void disconnect() {
    try {
      if (_socket != null) {
        _socket!.disconnect();
        _socket = null;
        _connectedToken = null;
        print('🔌 Socket successfully disconnected and cleared.');
      }
    } catch (e) {
      print('Error disconnecting socket: $e');
    }
  }

  // Safe no-op if the socket hasn't been initialized (or was already torn
  // down) — lets callers unregister listeners in dispose() without needing
  // to guard against the throwing `socket` getter themselves.
  static void off(String event, [void Function(dynamic)? handler]) {
    _socket?.off(event, handler);
  }

  static void on(String event, void Function(dynamic) handler) {
    _socket?.on(event, handler);
  }
}