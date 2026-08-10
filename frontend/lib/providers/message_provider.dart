import 'package:flutter/material.dart';
import '../models/message_model.dart';
import '../services/socket_service.dart';

class MessageProvider with ChangeNotifier {
  final List<MessageModel> _messages = [];
  bool _isLoading = false;
  bool _isRemoteUserTyping = false;

  List<MessageModel> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get isRemoteUserTyping => _isRemoteUserTyping;

  // Initialize socket listeners for a specific chat room
  void initChatListeners(String chatId) {
    _messages.clear();
    notifyListeners();

    // Join room via socket
    SocketService.joinChat(chatId);

    // Listen for incoming messages
    SocketService.socket.on('receive_message', (data) {
      if (data['chat_id'] == chatId) {
        _messages.add(MessageModel.fromJson(data));
        notifyListeners();
      }
    });

    // Listen for typing indicators
    SocketService.socket.on('user_typing', (data) {
      if (data['chatId'] == chatId) {
        _isRemoteUserTyping = data['isTyping'];
        notifyListeners();
      }
    });

    // Listen for message edits
    SocketService.socket.on('message_edited', (data) {
      final index = _messages.indexWhere((m) => m.messageId == data['message_id']);
      if (index != -1) {
        // Update message content locally
        notifyListeners();
      }
    });

    // Listen for message deletions
    SocketService.socket.on('message_deleted', (data) {
      _messages.removeWhere((m) => m.messageId == data['message_id']);
      notifyListeners();
    });
  }

  void sendMessage(String chatId, String content, {String? mediaUrl, String mediaType = 'text'}) {
    if (content.trim().isEmpty && mediaUrl == null) return;

    SocketService.sendMessage(
      chatId,
      content,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
    );
  }

  void sendTyping(String chatId, bool isTyping) {
    SocketService.sendTypingIndicator(chatId, isTyping);
  }

  void deleteMessage(String messageId, String chatId) {
    SocketService.socket.emit('delete_message', {
      'messageId': messageId,
      'chatId': chatId,
    });
  }
}