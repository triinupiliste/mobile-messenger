import 'dart:async';
import 'package:flutter/material.dart';
import '../models/chat_model.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../services/notification_service.dart';

class ChatProvider with ChangeNotifier {
  List<ChatModel> _chats = [];
  bool _isLoading = false;

  // Tracks a chat that's been swiped-to-delete but is still within its
  // "Undo" window — removed from the visible list immediately, only
  // persisted to the server once the timer fires without being undone.
  ChatModel? _pendingDeleteChat;
  int? _pendingDeleteIndex;
  Timer? _pendingDeleteTimer;

  List<ChatModel> get chats => _chats;
  bool get isLoading => _isLoading;

  // Total unread message count across all chats, used for the badge on the
  // bottom nav's Chats icon.
  int get totalUnreadCount => _chats.fold(0, (sum, c) => sum + c.unreadCount);

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

      // The server is the source of truth for mute state (it's what actually
      // suppresses push notifications). Re-seed the in-memory cache every time
      // the list loads so the mute/unmute UI reflects reality instead of
      // resetting to "unmuted" after an app restart.
      for (final chat in _chats) {
        NotificationSettingsService.setChatMuted(chat.chatId, chat.isMuted);
      }
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
            // A new message un-archives the chat (server does the same),
            // regardless of who sent it or who had archived it.
            isArchived: false,
            isMuted: _chats[index].isMuted,
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

  Future<void> toggleArchiveChat(String chatId) async {
    final index = _chats.indexWhere((c) => c.chatId == chatId);
    if (index == -1) return;

    final previousValue = _chats[index].isArchived;
    final newValue = !previousValue;

    // Optimistically update the UI, then persist to the server so the
    // archived state survives refreshes/restarts. Roll back on failure.
    _chats[index].isArchived = newValue;
    notifyListeners();

    try {
      await ApiService.setChatArchived(chatId, newValue);
    } catch (e) {
      debugPrint('Error updating chat archive state: $e');
      _chats[index].isArchived = previousValue;
      notifyListeners();
    }
  }

  // Removes the chat from the list right away for a snappy swipe-to-delete
  // UX, but only tells the server once the undo window has elapsed.
  void deleteChat(String chatId) {
    final index = _chats.indexWhere((c) => c.chatId == chatId);
    if (index == -1) return;

    // If another delete was already pending, commit it immediately first.
    _commitPendingDelete();

    _pendingDeleteChat = _chats[index];
    _pendingDeleteIndex = index;
    _chats.removeAt(index);
    notifyListeners();

    _pendingDeleteTimer = Timer(const Duration(seconds: 4), _commitPendingDelete);
  }

  void _commitPendingDelete() {
    _pendingDeleteTimer?.cancel();
    _pendingDeleteTimer = null;
    final chat = _pendingDeleteChat;
    _pendingDeleteChat = null;
    _pendingDeleteIndex = null;
    if (chat == null) return;

    ApiService.setChatDeleted(chat.chatId, true).catchError((e) {
      debugPrint('Error deleting chat: $e');
    });
  }

  void undoDeleteChat() {
    _pendingDeleteTimer?.cancel();
    _pendingDeleteTimer = null;
    final chat = _pendingDeleteChat;
    final index = _pendingDeleteIndex;
    _pendingDeleteChat = null;
    _pendingDeleteIndex = null;
    if (chat == null || index == null) return;

    _chats.insert(index.clamp(0, _chats.length), chat);
    notifyListeners();
  }
}