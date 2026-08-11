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

    _socket!.connect();

    _socket!.onConnect((_) {
      print('🔌 Connected to Socket.io server');
    });

    _socket!.onDisconnect((_) {
      print('🔌 Disconnected from Socket.io server');
    });
  }

  static void joinChat(String chatId) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('join_chat', chatId);
    }
  }

  static void sendMessage(String chatId, String content, {String? mediaUrl, String mediaType = 'text'}) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('send_message', {
        'chatId': chatId,
        'content': content,
        'mediaUrl': mediaUrl,
        'mediaType': mediaType,
      });
    }
  }

  static void sendTypingIndicator(String chatId, bool isTyping) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('typing', {'chatId': chatId, 'isTyping': isTyping});
    }
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