import 'package:flutter/material.dart';
import '../models/chat_model.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

class ChatProvider with ChangeNotifier {
  List<ChatModel> _chats = [];
  bool _isLoading = false;

  List<ChatModel> get chats => _chats;
  bool get isLoading => _isLoading;

  ChatProvider() {
    _initGlobalSocketListener();
  }

  Future<void> fetchChats() async {
    _isLoading = true;
    notifyListeners();

    try {
      final data = await ApiService.getChats();
      _chats = data.map((json) => ChatModel.fromJson(json)).toList();
      _sortChats();
    } catch (e) {
      debugPrint('Error fetching chats: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  // Mandatory Requirement: Sort chat list by the time of the last message received or sent
  void _sortChats() {
    _chats.sort((a, b) {
      final timeA = a.lastMessageTime ?? DateTime(2000);
      final timeB = b.lastMessageTime ?? DateTime(2000);
      return timeB.compareTo(timeA); // Newest first
    });
  }

  // Listen globally for incoming messages to update the chat list preview and sorting
  void _initGlobalSocketListener() {
    // Ensure socket is initialized, then listen for updates
    try {
      SocketService.socket.on('receive_message', (data) {
        final chatId = data['chat_id'] ?? data['chatId'];
        final index = _chats.indexWhere((c) => c.chatId == chatId);

        if (index != -1) {
          // Update last message snippet and timestamp for the chat list item.
          // Unread count is left as-is here; it's refreshed accurately via fetchChats().
          _chats[index] = ChatModel(
            chatId: _chats[index].chatId,
            contactId: _chats[index].contactId,
            contactName: _chats[index].contactName,
            contactAvatar: _chats[index].contactAvatar,
            lastMessage: data['content'],
            lastMessageType: data['media_type'] ?? data['mediaType'],
            lastMessageTime: data['created_at'] != null 
                ? DateTime.parse(data['created_at']) 
                : DateTime.now(),
            lastMessageSenderId: data['sender_id'],
            unreadCount: _chats[index].unreadCount,
            isArchived: _chats[index].isArchived,
          );
          _sortChats();
          notifyListeners();
        } else {
          // If it's a brand new chat, fetch the full list again
          fetchChats();
        }
      });
    } catch (e) {
      debugPrint('Socket listener initialization deferred: $e');
    }
  }

  void toggleArchiveChat(String chatId) {
    final index = _chats.indexWhere((c) => c.chatId == chatId);
    if (index != -1) {
      _chats[index].isArchived = !_chats[index].isArchived;
      notifyListeners();
    }
  }
}