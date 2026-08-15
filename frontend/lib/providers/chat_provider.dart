import 'dart:async';
import 'package:flutter/material.dart';
import '../models/chat_model.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../services/notification_service.dart';

class ChatProvider with ChangeNotifier {
  List<ChatModel> _chats = [];
  bool _isLoading = false;
  bool _socketListenerAttached = false;
  String? _currentUserId;

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

    // The socket may not have been initialized yet the first time this ran
    // (e.g. right at app startup, before login finishes connecting it) —
    // retry attaching here so live updates start working as soon as it is.
    _initGlobalSocketListener();
    unawaited(_ensureCurrentUserId());

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

  Future<void> _ensureCurrentUserId() async {
    if (_currentUserId != null) return;
    try {
      final profile = await ApiService.getProfile();
      _currentUserId = profile['id']?.toString() ?? profile['user_id']?.toString();
    } catch (e) {
      debugPrint('Error fetching current user id: $e');
    }
  }

  // Listen globally for incoming messages to update the chat list preview and sorting
  void _initGlobalSocketListener() {
    if (_socketListenerAttached) return;
    // Ensure socket is initialized, then listen for updates
    try {
      SocketService.socket.on('receive_message', (data) {
        final chatId = data['chat_id'] ?? data['chatId'];
        final index = _chats.indexWhere((c) => c.chatId == chatId);
        final senderId = data['sender_id']?.toString();
        final isFromMe = _currentUserId != null && senderId == _currentUserId;
        // If this chat is the one currently open on screen, its messages are
        // already visible live there and get marked read — don't count them
        // as unread on the list.
        final chatIsActive = ActiveChatTracker.isChatActive(chatId?.toString() ?? '');

        if (index != -1) {
          final existing = _chats[index];
          _chats[index] = ChatModel(
            chatId: existing.chatId,
            contactId: existing.contactId,
            contactName: existing.contactName,
            contactAvatar: existing.contactAvatar,
            lastMessage: data['content'],
            lastMessageType: data['media_type'] ?? data['mediaType'],
            lastMessageTime: data['created_at'] != null 
                ? DateTime.parse(data['created_at']) 
                : DateTime.now(),
            lastMessageSenderId: data['sender_id'],
            // Bump the unread badge/bold state immediately when a message
            // arrives from the other person while its chat isn't open. If
            // the chat is open right now, it's immediately visible/read (and
            // the chat room screen tells the backend so too), so force it
            // back to 0 instead of leaving a stale count from before it was
            // opened.
            unreadCount: chatIsActive
                ? 0
                : (!isFromMe ? existing.unreadCount + 1 : existing.unreadCount),
            // A new message un-archives the chat (server does the same),
            // regardless of who sent it or who had archived it.
            isArchived: false,
            isMuted: existing.isMuted,
          );
          _sortChats();
          notifyListeners();
        } else {
          // If it's a brand new chat, fetch the full list again
          fetchChats();
        }
      });

      // The other participant removed us as a friend — the chat disappears
      // from our list too, live, without needing to reopen the screen.
      SocketService.socket.on('friend_removed', (data) {
        final chatId = data['chatId'];
        final removed = _chats.any((c) => c.chatId == chatId);
        if (!removed) return;
        _chats.removeWhere((c) => c.chatId == chatId);
        notifyListeners();
      });

      _socketListenerAttached = true;
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

    _pendingDeleteTimer = Timer(const Duration(seconds: 5), _commitPendingDelete);
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

  // Ends the friendship: removes the chat from the list immediately (for
  // both participants — the backend hides it and notifies the other user's
  // client too) with no undo, since this is already behind a confirmation
  // dialog. Message history is preserved server-side in case they reconnect.
  Future<void> removeFriend(String chatId) async {
    final index = _chats.indexWhere((c) => c.chatId == chatId);
    final removedChat = index != -1 ? _chats[index] : null;
    if (index != -1) {
      _chats.removeAt(index);
      notifyListeners();
    }

    try {
      await ApiService.removeFriend(chatId);
    } catch (e) {
      if (removedChat != null) {
        _chats.insert(index.clamp(0, _chats.length), removedChat);
        notifyListeners();
      }
      rethrow;
    }
  }
}