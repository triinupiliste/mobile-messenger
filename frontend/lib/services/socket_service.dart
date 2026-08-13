import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'storage_service.dart';

class SocketService {
  static IO.Socket? _socket;

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

    if (_socket != null && _socket!.connected) return;

    _socket = IO.io('http://localhost:5000', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'auth': {'token': token},
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
    _socket?.emit('join_chat', chatId);
  }

  static void sendMessage(String chatId, String content, {String? mediaUrl, String mediaType = 'text'}) {
    _socket?.emit('send_message', {
      'chatId': chatId,
      'content': content,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
    });
  }

  static void sendTypingIndicator(String chatId, bool isTyping) {
    _socket?.emit('typing', {'chatId': chatId, 'isTyping': isTyping});
  }

  static void disconnect() {
    try {
      if (_socket != null) {
        _socket!.disconnect();
        _socket = null;
        print('🔌 Socket successfully disconnected and cleared.');
      }
    } catch (e) {
      print('Error disconnecting socket: $e');
    }
  }
}