import 'dart:async';
import 'package:flutter/material.dart';
import '../constants/socket_events.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/push_notification_service.dart';
import '../services/socket_service.dart';

// Owns the message list + real-time socket sync for a single, specific chat
// room. Deliberately scoped per chat room (created fresh via
// ChangeNotifierProvider right where ChatRoomScreen is built, NOT registered
// globally in main.dart) since message state is only ever needed by that one
// screen — unlike ChatProvider/InviteProvider, which are genuinely app-wide.
//
// Pure UI concerns (scroll position, reply-compose box, recording/upload
// spinners, the message TextField) deliberately stay in ChatRoomScreen's
// State instead of moving here — they're about what's currently rendered,
// not about the underlying chat data.
class MessageProvider with ChangeNotifier {
  MessageProvider(this.chatId);

  final String chatId;

  // Tracks messages this device sent but hasn't heard back from the server
  // about yet, keyed by a locally-generated tempId. If the server doesn't
  // confirm (echo) a message back within this window, it's marked 'failed'
  // so the user gets visual feedback and a retry option instead of the
  // message silently vanishing (e.g. when offline or the socket drops).
  static const Duration _sendTimeout = Duration(seconds: 10);
  final Map<String, Timer> _pendingSendTimers = {};

  final List<Map<String, dynamic>> _messages = [];
  bool _isRemoteUserTyping = false;
  bool _isLoadingHistory = true;
  String? _currentUserId;

  Timer? _typingTimer;
  bool _isTyping = false;

  List<Map<String, dynamic>> get messages => _messages;
  bool get isRemoteUserTyping => _isRemoteUserTyping;
  bool get isLoadingHistory => _isLoadingHistory;
  String? get currentUserId => _currentUserId;

  // Stored so dispose() can unregister exactly these callbacks — without this,
  // reopening the same chat repeatedly stacks duplicate listeners on the
  // shared socket singleton, which stops new events from reliably reaching
  // the currently-visible screen (an earlier, already-disposed listener can
  // throw and prevent later listeners for the same event from running).
  late final void Function(dynamic) _onConnect;
  late final void Function(dynamic) _onReceiveMessage;
  late final void Function(dynamic) _onErrorFeedbackMarksFailed;
  late final void Function(dynamic) _onUserTyping;
  late final void Function(dynamic) _onMessageEdited;
  late final void Function(dynamic) _onMessageDeleted;
  late final void Function(dynamic) _onMessagesRead;

  // Joins the chat room, registers all real-time listeners, and loads
  // persisted history. Call once, right after construction.
  Future<void> init() async {
    // Catches up on read-receipts for messages that arrived while the app
    // was backgrounded (and so were deliberately NOT marked read yet, since
    // the user wasn't actually looking at them) — now that they've resumed
    // the app with this chat still the one on screen, it's fair to treat
    // them as read.
    AppLifecycleTracker.addForegroundListener(_onAppForegrounded);

    // socket.io-client buffers emits until the connection is established,
    // so we don't need to gate this on `connected` — doing so previously
    // caused join/send calls to be silently dropped during a reconnect race.
    SocketService.joinChat(chatId);

    // Re-join whenever the socket (re)connects — e.g. after the app is
    // backgrounded and the connection drops — otherwise this chat stops
    // receiving real-time updates until it's reopened.
    _onConnect = (_) {
      SocketService.joinChat(chatId);
    };
    SocketService.on(SocketEvents.connect, _onConnect);

    _onReceiveMessage = (data) {
      if (data['chat_id'] != chatId) return;
      final incoming = Map<String, dynamic>.from(data);
      final tempId = incoming['tempId']?.toString();

      final pendingIndex = tempId != null ? _messages.indexWhere((m) => m['_tempId'] == tempId) : -1;
      if (pendingIndex != -1) {
        // This confirms a message this device just sent — replace the
        // optimistic placeholder with the server-confirmed message.
        _messages[pendingIndex] = incoming;
      } else {
        _messages.add(incoming);
      }
      if (tempId != null) {
        _pendingSendTimers.remove(tempId)?.cancel();
      }
      notifyListeners();

      // Let the sender know their message actually reached this device live,
      // so their tick updates from 'sent' to 'delivered'. This is accurate
      // regardless of whether the app is foregrounded — the message really
      // was delivered to this device's live connection.
      if (_currentUserId != null && incoming['sender_id'] != _currentUserId) {
        final messageId = incoming['id']?.toString();
        if (messageId != null && messageId.isNotEmpty) {
          SocketService.updateMessageStatus(chatId, messageId, 'delivered');
        }

        // But only mark it 'read' (and cancel the tray notification) if the
        // app is actually in the foreground right now. This screen can stay
        // mounted (and this listener stays registered) even while the app is
        // backgrounded — e.g. the user switched to another app without
        // navigating away from this chat — in which case the message hasn't
        // really been seen yet.
        if (AppLifecycleTracker.isForeground) {
          // This chat is open right now, so the message is immediately visible
          // and counts as read — tell the backend straight away instead of
          // waiting for the next time this screen is opened. Otherwise the
          // chat list still shows it as unread once you navigate back, since
          // its unread count is re-fetched fresh from the server.
          ApiService.markChatMessagesRead(chatId);
          PushNotificationService.cancelForChat(chatId);
        }
      }
    };
    SocketService.on(SocketEvents.receiveMessage, _onReceiveMessage);

    // If the server rejects a send outright (e.g. an unexpected error while
    // saving), mark that specific pending message failed immediately instead
    // of waiting out the full send timeout.
    _onErrorFeedbackMarksFailed = (data) {
      final tempId = data['tempId']?.toString();
      if (tempId == null) return;
      _pendingSendTimers.remove(tempId)?.cancel();
      final index = _messages.indexWhere((m) => m['_tempId'] == tempId);
      if (index != -1) {
        _messages[index]['status'] = 'failed';
        notifyListeners();
      }
    };
    SocketService.on(SocketEvents.errorFeedback, _onErrorFeedbackMarksFailed);

    _onUserTyping = (data) {
      if (data['chatId'] == chatId) {
        _isRemoteUserTyping = data['isTyping'] == true;
        notifyListeners();
      }
    };
    SocketService.on(SocketEvents.userTyping, _onUserTyping);

    _onMessageEdited = (data) {
      final index = _messages.indexWhere((m) => m['id'] == data['id']);
      if (index != -1) {
        _messages[index]['content'] = data['content'];
        _messages[index]['is_edited'] = true;
        notifyListeners();
      }
    };
    SocketService.on(SocketEvents.messageEdited, _onMessageEdited);

    _onMessageDeleted = (data) {
      final index = _messages.indexWhere((m) => m['id'] == data['id']);
      if (index != -1) {
        _messages[index]['content'] = null;
        _messages[index]['media_url'] = null;
        _messages[index]['is_deleted'] = true;
        notifyListeners();
      }
    };
    SocketService.on(SocketEvents.messageDeleted, _onMessageDeleted);

    // When the other participant reads this chat, mark my sent messages as
    // 'read' so the delivery ticks update in real time.
    _onMessagesRead = (data) {
      if (data['chatId'] != chatId) return;
      // If I'm the one who just read the chat, my own sent messages weren't affected.
      if (_currentUserId != null && data['readerId'] == _currentUserId) return;
      var changed = false;
      for (final m in _messages) {
        if (m['sender_id'] == _currentUserId && m['status'] != 'read') {
          m['status'] = 'read';
          changed = true;
        }
      }
      if (changed) notifyListeners();
    };
    SocketService.on(SocketEvents.messagesRead, _onMessagesRead);

    await _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final profile = await ApiService.getProfile();
      _currentUserId = profile['id']?.toString() ?? profile['user_id']?.toString();

      final history = await ApiService.getMessages(chatId);
      _messages
        ..clear()
        ..addAll(history.whereType<Map>().map((m) => Map<String, dynamic>.from(m)));
      _isLoadingHistory = false;
      notifyListeners();

      // Mark the other participant's messages as read now that this chat is open.
      ApiService.markChatMessagesRead(chatId);
    } catch (e) {
      _isLoadingHistory = false;
      notifyListeners();
    }
  }

  void sendMessage(
    String content, {
    String? mediaUrl,
    String mediaType = 'text',
    Map<String, dynamic>? replyingTo,
  }) {
    if (content.trim().isEmpty && mediaUrl == null) return;

    final tempId = 'temp_${DateTime.now().microsecondsSinceEpoch}';

    _messages.add({
      '_tempId': tempId,
      'id': '',
      'chat_id': chatId,
      'sender_id': _currentUserId,
      'content': content,
      'media_url': mediaUrl,
      'media_type': mediaType,
      'status': 'sending',
      'is_edited': false,
      'is_deleted': false,
      'reply_to_id': replyingTo?['id'],
      'reply_to': replyingTo == null
          ? null
          : {
              'id': replyingTo['id'],
              'sender_id': replyingTo['sender_id'],
              'content': replyingTo['content'],
              'media_type': replyingTo['media_type'],
              'is_deleted': replyingTo['is_deleted'] ?? false,
            },
      'created_at': DateTime.now().toIso8601String(),
    });
    notifyListeners();

    SocketService.sendMessage(
      chatId,
      content,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      tempId: tempId,
      replyToId: replyingTo?['id']?.toString(),
    );
    _startSendTimeout(tempId);

    if (_isTyping) {
      _isTyping = false;
      SocketService.sendTypingIndicator(chatId, false);
    }
  }

  void _startSendTimeout(String tempId) {
    _pendingSendTimers[tempId]?.cancel();
    _pendingSendTimers[tempId] = Timer(_sendTimeout, () {
      _pendingSendTimers.remove(tempId);
      final index = _messages.indexWhere((m) => m['_tempId'] == tempId);
      if (index != -1 && _messages[index]['status'] == 'sending') {
        _messages[index]['status'] = 'failed';
        notifyListeners();
      }
    });
  }

  // Re-sends a message that previously failed (e.g. connection dropped, or
  // the server rejected it), reusing the same tempId so the retried send
  // still replaces this same bubble once confirmed.
  void retryMessage(String tempId) {
    final index = _messages.indexWhere((m) => m['_tempId'] == tempId);
    if (index == -1) return;

    final msg = _messages[index];
    msg['status'] = 'sending';
    notifyListeners();

    SocketService.sendMessage(
      chatId,
      msg['content'] ?? '',
      mediaUrl: msg['media_url'],
      mediaType: msg['media_type'] ?? 'text',
      tempId: tempId,
      replyToId: msg['reply_to_id']?.toString(),
    );
    _startSendTimeout(tempId);
  }

  void editMessage(String messageId, String newContent) {
    SocketService.socket.emit(SocketEvents.editMessage, {
      'messageId': messageId,
      'chatId': chatId,
      'newContent': newContent,
    });
  }

  void deleteMessage(String messageId) {
    SocketService.socket.emit(SocketEvents.deleteMessage, {
      'messageId': messageId,
      'chatId': chatId,
    });
  }

  void handleTyping() {
    if (!_isTyping) {
      _isTyping = true;
      SocketService.sendTypingIndicator(chatId, true);
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      _isTyping = false;
      SocketService.sendTypingIndicator(chatId, false);
    });
  }

  void _onAppForegrounded() {
    ApiService.markChatMessagesRead(chatId);
    PushNotificationService.cancelForChat(chatId);
  }

  @override
  void dispose() {
    AppLifecycleTracker.removeForegroundListener(_onAppForegrounded);
    SocketService.off(SocketEvents.connect, _onConnect);
    SocketService.off(SocketEvents.receiveMessage, _onReceiveMessage);
    SocketService.off(SocketEvents.errorFeedback, _onErrorFeedbackMarksFailed);
    SocketService.off(SocketEvents.userTyping, _onUserTyping);
    SocketService.off(SocketEvents.messageEdited, _onMessageEdited);
    SocketService.off(SocketEvents.messageDeleted, _onMessageDeleted);
    SocketService.off(SocketEvents.messagesRead, _onMessagesRead);
    _typingTimer?.cancel();
    for (final timer in _pendingSendTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }
}
