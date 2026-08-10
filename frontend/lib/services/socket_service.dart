import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'storage_service.dart';

class SocketService {
  static late IO.Socket socket;

  static Future<void> initSocket() async {
    final token = await StorageService.getToken();
    if (token == null) return;

    socket = IO.io('http://10.0.2.2:5000', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'auth': {'token': token},
    });

    socket.connect();

    socket.onConnect((_) {
      print('🔌 Connected to Socket.io server');
    });

    socket.onDisconnect((_) {
      print('🔌 Disconnected from Socket.io server');
    });
  }

  static void joinChat(String chatId) {
    socket.emit('join_chat', chatId);
  }

  static void sendMessage(String chatId, String content, {String? mediaUrl, String mediaType = 'text'}) {
    socket.emit('send_message', {
      'chatId': chatId,
      'content': content,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
    });
  }

  static void sendTypingIndicator(String chatId, bool isTyping) {
    socket.emit('typing', {'chatId': chatId, 'isTyping': isTyping});
  }

  static void disconnect() {
    if (socket.connected) {
      socket.disconnect();
    }
  }
}