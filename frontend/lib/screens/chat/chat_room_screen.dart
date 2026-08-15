import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../providers/chat_provider.dart';
import '../../services/api_service.dart';
import '../../services/socket_service.dart';
import '../../services/audio_service.dart';
import '../../services/notification_service.dart';
import '../../services/push_notification_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/chat/message_bubble.dart';
import '../../widgets/chat/typing_indicator_bubble.dart';
import '../../widgets/common/user_avatar.dart';

class ChatRoomScreen extends StatefulWidget {
  final String chatId;
  final String contactId;
  final String contactName;

  const ChatRoomScreen({
    super.key,
    required this.chatId,
    this.contactId = '',
    required this.contactName,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener = ItemPositionsListener.create();
  final AudioService _audioService = AudioService();

  // Tracks messages this device sent but hasn't heard back from the server
  // about yet, keyed by a locally-generated tempId. If the server doesn't
  // confirm (echo) a message back within this window, it's marked 'failed'
  // so the user gets visual feedback and a retry option instead of the
  // message silently vanishing (e.g. when offline or the socket drops).
  static const Duration _sendTimeout = Duration(seconds: 10);
  final Map<String, Timer> _pendingSendTimers = {};
  
  final List<Map<String, dynamic>> _messages = [];
  bool _isRemoteUserTyping = false;
  Timer? _typingTimer;
  bool _isTyping = false;
  bool _isRecording = false;
  bool _isLoadingHistory = true;
  bool _isUploadingMedia = false;
  bool _showJumpToLatestButton = false;
  String? _currentUserId;
  Map<String, dynamic>? _replyingTo;

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
  late final void Function(dynamic) _onErrorFeedback;

  @override
  void initState() {
    super.initState();

    // Mark this chat as the one currently on screen, so a foreground push
    // notification for it can be suppressed (already visible live here).
    ActiveChatTracker.setActiveChat(widget.chatId);

    // Whether opened via a notification tap or directly through the app, its
    // messages are read the moment this screen is on screen — clear any
    // pending tray notification for it instead of leaving it lingering.
    PushNotificationService.cancelForChat(widget.chatId);

    // 1. Join the specific chat room via socket
    SocketService.joinChat(widget.chatId);

    // Re-join whenever the socket (re)connects — e.g. after the app is backgrounded
    // and the connection drops — otherwise this screen stops receiving real-time
    // updates for its own sent messages until it's reopened.
    _onConnect = (_) {
      SocketService.joinChat(widget.chatId);
    };
    SocketService.on('connect', _onConnect);

    // 2. Listen for incoming real-time socket events
    _onReceiveMessage = (data) {
      if (data['chat_id'] != widget.chatId) return;
      final incoming = Map<String, dynamic>.from(data);
      final tempId = incoming['tempId']?.toString();

      setState(() {
        final pendingIndex = tempId != null ? _messages.indexWhere((m) => m['_tempId'] == tempId) : -1;
        if (pendingIndex != -1) {
          // This confirms a message this device just sent — replace the
          // optimistic placeholder with the server-confirmed message.
          _messages[pendingIndex] = incoming;
        } else {
          _messages.add(incoming);
        }
      });
      if (tempId != null) {
        _pendingSendTimers.remove(tempId)?.cancel();
      }
      _scrollToBottom();

      // Let the sender know their message actually reached this device live,
      // so their tick updates from 'sent' to 'delivered'.
      if (_currentUserId != null && incoming['sender_id'] != _currentUserId) {
        final messageId = incoming['id']?.toString();
        if (messageId != null && messageId.isNotEmpty) {
          SocketService.updateMessageStatus(widget.chatId, messageId, 'delivered');
        }

        // This chat is open right now, so the message is immediately visible
        // and counts as read — tell the backend straight away instead of
        // waiting for the next time this screen is opened. Otherwise the
        // chat list still shows it as unread once you navigate back, since
        // its unread count is re-fetched fresh from the server.
        ApiService.markChatMessagesRead(widget.chatId);
        PushNotificationService.cancelForChat(widget.chatId);
      }
    };
    SocketService.on('receive_message', _onReceiveMessage);

    // If the server rejects a send outright (e.g. an unexpected error while
    // saving), mark that specific pending message failed immediately instead
    // of waiting out the full send timeout.
    _onErrorFeedbackMarksFailed = (data) {
      final tempId = data['tempId']?.toString();
      if (tempId == null) return;
      _pendingSendTimers.remove(tempId)?.cancel();
      final index = _messages.indexWhere((m) => m['_tempId'] == tempId);
      if (index != -1 && mounted) {
        setState(() => _messages[index]['status'] = 'failed');
      }
    };
    SocketService.on('error_feedback', _onErrorFeedbackMarksFailed);

    _onUserTyping = (data) {
      if (data['chatId'] == widget.chatId) {
        final isTyping = data['isTyping'] == true;
        final wasTyping = _isRemoteUserTyping;
        setState(() {
          _isRemoteUserTyping = isTyping;
        });
        // Keep the latest message in view as the typing bubble grows the
        // column below the list, pushing content up.
        if (isTyping && !wasTyping) {
          _scrollToBottom();
        }
      }
    };
    SocketService.on('user_typing', _onUserTyping);

    _onMessageEdited = (data) {
      setState(() {
        final index = _messages.indexWhere((m) => m['id'] == data['id']);
        if (index != -1) {
          _messages[index]['content'] = data['content'];
          _messages[index]['is_edited'] = true;
        }
      });
    };
    SocketService.on('message_edited', _onMessageEdited);

    _onMessageDeleted = (data) {
      setState(() {
        final index = _messages.indexWhere((m) => m['id'] == data['id']);
        if (index != -1) {
          _messages[index]['content'] = null;
          _messages[index]['media_url'] = null;
          _messages[index]['is_deleted'] = true;
        }
      });
    };
    SocketService.on('message_deleted', _onMessageDeleted);

    // When the other participant reads this chat, mark my sent messages as 'read'
    // so the delivery ticks update in real time.
    _onMessagesRead = (data) {
      if (data['chatId'] != widget.chatId) return;
      // If I'm the one who just read the chat, my own sent messages weren't affected.
      if (_currentUserId != null && data['readerId'] == _currentUserId) return;
      setState(() {
        for (final m in _messages) {
          if (m['sender_id'] == _currentUserId && m['status'] != 'read') {
            m['status'] = 'read';
          }
        }
      });
    };
    SocketService.on('messages_read', _onMessagesRead);

    _onErrorFeedback = (data) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(data['message']?.toString() ?? 'Something went wrong.')),
      );
    };
    SocketService.on('error_feedback', _onErrorFeedback);

    // Track which messages are actually on screen so we can show a "more
    // messages" pill whenever there's an unread message hidden below the fold.
    _itemPositionsListener.itemPositions.addListener(_handleItemPositionsChanged);

    // 3. Load the persisted message history for this chat
    _loadHistory();
  }

  void _handleItemPositionsChanged() {
    if (_messages.isEmpty) return;
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    final lastVisibleIndex = positions.map((p) => p.index).reduce((a, b) => a > b ? a : b);

    // Only show the pill when an unread message from the other participant is
    // still hidden below the current viewport — not just whenever we've
    // scrolled away from the very bottom. Once a message has been read
    // (locally, or already marked read in a previous visit to this chat),
    // it no longer counts, so the pill won't reappear for old, read history.
    final hasUnreadBelow = _messages.asMap().entries.any((entry) =>
        entry.key > lastVisibleIndex &&
        entry.value['sender_id'] != _currentUserId &&
        entry.value['status'] != 'read' &&
        entry.value['is_deleted'] != true);

    if (hasUnreadBelow != _showJumpToLatestButton && mounted) {
      setState(() => _showJumpToLatestButton = hasUnreadBelow);
    }
  }

  String _formatTimestamp(dynamic createdAt) {
    if (createdAt == null) return '';
    final parsed = DateTime.tryParse(createdAt.toString());
    if (parsed == null) return '';

    final local = parsed.toLocal();
    final time = DateFormat('HH:mm').format(local);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(local.year, local.month, local.day);
    final daysAgo = today.difference(messageDay).inDays;

    if (daysAgo <= 0) {
      // Sent today: time only.
      return time;
    } else if (daysAgo == 1) {
      // Sent yesterday.
      return 'Yesterday $time';
    } else if (daysAgo < 7) {
      // Sent within the last week: day of week + time, e.g. "Mon 14:32".
      return '${DateFormat('EEE').format(local)} $time';
    } else {
      // Older than a week: date + time, e.g. "14 Aug 14:32". The year is only
      // included when the message isn't from the current year.
      final datePattern = local.year == now.year ? 'd MMM' : 'd MMM yyyy';
      return '${DateFormat(datePattern).format(local)} $time';
    }
  }

  Future<void> _loadHistory() async {
    try {
      final profile = await ApiService.getProfile();
      _currentUserId = profile['id']?.toString() ?? profile['user_id']?.toString();

      final history = await ApiService.getMessages(widget.chatId);
      if (!mounted) return;

      setState(() {
        _messages
          ..clear()
          ..addAll(history.whereType<Map>().map((m) => Map<String, dynamic>.from(m)));
        _isLoadingHistory = false;
      });
      _jumpToInitialPosition();

      // Mark the other participant's messages as read now that this chat is open.
      ApiService.markChatMessagesRead(widget.chatId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingHistory = false);
    }
  }

  // Jumps straight to the first unread message (from the other participant) so the
  // user lands right where they left off, instead of always landing at the bottom.
  // If everything is already read, it lands on the last message like normal.
  void _jumpToInitialPosition() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_itemScrollController.isAttached || _messages.isEmpty) return;

      final firstUnreadIndex = _messages.indexWhere((m) =>
          m['sender_id'] != _currentUserId &&
          m['status'] != 'read' &&
          m['is_deleted'] != true);

      if (firstUnreadIndex == -1) {
        // The sentinel item (index == _messages.length) has ~zero height, so
        // aligning its top edge to the bottom of the viewport (alignment 1.0)
        // is equivalent to flushing the real last message against the bottom.
        _itemScrollController.jumpTo(index: _messages.length, alignment: 1.0);
      } else {
        _itemScrollController.jumpTo(index: firstUnreadIndex, alignment: 0.0);
      }
    });
  }

  // Jumps to the latest message — used when a new message arrives (sent or
  // received) while the chat is already open.
  //
  // Note: this intentionally uses jumpTo() instead of the animated scrollTo().
  // scrollTo() estimates the target item's position before it has actually
  // been laid out (since it was just inserted), animates towards that
  // estimate, then corrects once the real size is known — which shows up as
  // a visible "scroll then snap back" glitch that can hide the newest
  // message. jumpTo() performs the same estimate+correct internally but
  // instantly, so any correction is imperceptible.
  //
  // We target the sentinel item (index == _messages.length, ~zero height)
  // rather than the last message itself: alignment positions an item's TOP
  // edge, so aligning the real last message's top to the viewport's bottom
  // (alignment 1.0) would push almost the whole bubble off-screen. Aligning
  // the near-zero-height sentinel's top to the bottom instead flushes the
  // real content's bottom edge against the viewport's bottom, as intended.
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_itemScrollController.isAttached || _messages.isEmpty) return;
      _itemScrollController.jumpTo(index: _messages.length, alignment: 1.0);
    });
  }

  void _handleTyping(String text) {
    if (!_isTyping) {
      _isTyping = true;
      SocketService.sendTypingIndicator(widget.chatId, true);
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      _isTyping = false;
      SocketService.sendTypingIndicator(widget.chatId, false);
    });
  }

  // Sets a message as the target of the next send, shown as a preview above
  // the input bar (and rendered as a quoted excerpt on the sent message).
  void _startReply(Map<String, dynamic> msg) {
    if ((msg['id'] ?? '').toString().isEmpty) return; // don't reply to a still-sending/failed message
    setState(() => _replyingTo = msg);
  }

  void _cancelReply() {
    setState(() => _replyingTo = null);
  }

  String _replySenderLabel(Map<String, dynamic> replyTo) {
    return replyTo['sender_id'] == _currentUserId ? 'You' : widget.contactName;
  }

  String _replyPreviewText(Map<String, dynamic> replyTo) {
    if (replyTo['is_deleted'] == true) return 'This message was deleted';
    final content = (replyTo['content'] ?? '').toString();
    if (content.isNotEmpty) return content;
    switch (replyTo['media_type']) {
      case 'image':
        return 'Photo';
      case 'video':
        return 'Video';
      case 'audio':
        return 'Voice message';
      default:
        return '';
    }
  }

  void _sendMessage({String? mediaUrl, String mediaType = 'text'}) {
    final content = _messageController.text.trim();
    if (content.isEmpty && mediaUrl == null) return;

    final tempId = 'temp_${DateTime.now().microsecondsSinceEpoch}';
    final replyingTo = _replyingTo;

    setState(() {
      _messages.add({
        '_tempId': tempId,
        'id': '',
        'chat_id': widget.chatId,
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
      _replyingTo = null;
    });
    _scrollToBottom();

    SocketService.sendMessage(
      widget.chatId,
      content,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      tempId: tempId,
      replyToId: replyingTo?['id']?.toString(),
    );
    _startSendTimeout(tempId);

    _messageController.clear();
    if (_isTyping) {
      _isTyping = false;
      SocketService.sendTypingIndicator(widget.chatId, false);
    }
  }

  void _startSendTimeout(String tempId) {
    _pendingSendTimers[tempId]?.cancel();
    _pendingSendTimers[tempId] = Timer(_sendTimeout, () {
      _pendingSendTimers.remove(tempId);
      if (!mounted) return;
      final index = _messages.indexWhere((m) => m['_tempId'] == tempId);
      if (index != -1 && _messages[index]['status'] == 'sending') {
        setState(() => _messages[index]['status'] = 'failed');
      }
    });
  }

  // Re-sends a message that previously failed (e.g. connection dropped, or
  // the server rejected it), reusing the same tempId so the retried send
  // still replaces this same bubble once confirmed.
  void _retryMessage(String tempId) {
    final index = _messages.indexWhere((m) => m['_tempId'] == tempId);
    if (index == -1) return;

    final msg = _messages[index];
    setState(() => msg['status'] = 'sending');

    SocketService.sendMessage(
      widget.chatId,
      msg['content'] ?? '',
      mediaUrl: msg['media_url'],
      mediaType: msg['media_type'] ?? 'text',
      tempId: tempId,
      replyToId: msg['reply_to_id']?.toString(),
    );
    _startSendTimeout(tempId);
  }

  Future<void> _editMessage(String messageId, String currentContent) async {
    final controller = TextEditingController(text: currentContent);
    final newContent = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          decoration: const InputDecoration(hintText: 'Message'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newContent == null || newContent.isEmpty || newContent == currentContent) return;

    SocketService.socket.emit('edit_message', {
      'messageId': messageId,
      'chatId': widget.chatId,
      'newContent': newContent,
    });
  }

  Future<void> _confirmDeleteMessage(String messageId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message'),
        content: const Text('This message will be deleted for everyone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    SocketService.socket.emit('delete_message', {
      'messageId': messageId,
      'chatId': widget.chatId,
    });
  }

  Future<void> _pickAndSendMedia(ImageSource source) async {
    final picker = ImagePicker();
    XFile? pickedFile;
    String mediaKind;

    if (source == ImageSource.gallery) {
      // Open the full gallery and let the user pick either a photo or a video directly.
      pickedFile = await picker.pickMedia();
      mediaKind = pickedFile != null ? _guessMediaType(pickedFile) : 'image';
    } else {
      final choice = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: Icon(Icons.photo, color: AppColors.primary),
                title: const Text('Photo'),
                onTap: () => Navigator.pop(context, 'image'),
              ),
              ListTile(
                leading: Icon(Icons.videocam, color: AppColors.primary),
                title: const Text('Video'),
                onTap: () => Navigator.pop(context, 'video'),
              ),
            ],
          ),
        ),
      );

      if (choice == null) return;
      mediaKind = choice;

      if (choice == 'image') {
        pickedFile = await picker.pickImage(source: source);
      } else {
        pickedFile = await picker.pickVideo(source: source);
      }
    }

    if (pickedFile != null) {
      final file = File(pickedFile.path);
      final fileSizeInMB = await file.length() / (1024 * 1024);

      if (fileSizeInMB > 20) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Media file size exceeds the 20MB limit.')),
          );
        }
        return;
      }

      await _uploadAndSendMedia(file, mediaKind);
    }
  }

  String _guessMediaType(XFile file) {
    const videoExtensions = {'mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v', '3gp'};
    final ext = file.path.split('.').last.toLowerCase();
    return videoExtensions.contains(ext) ? 'video' : 'image';
  }

  Future<void> _uploadAndSendMedia(File file, String mediaType) async {
    setState(() => _isUploadingMedia = true);
    try {
      final url = await ApiService.uploadMedia(file);
      _sendMessage(mediaUrl: url, mediaType: mediaType);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send $mediaType: ${e.toString().replaceFirst('Exception: ', '')}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingMedia = false);
    }
  }

  Future<void> _confirmRemoveFriend() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Friend'),
        content: Text(
          'Remove ${widget.contactName} as a friend? This will remove the chat '
          'for both of you. If you add each other again later, your message '
          'history will be there.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await context.read<ChatProvider>().removeFriend(widget.chatId);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to remove friend: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  Future<void> _viewProfile() async {
    if (widget.contactId.isEmpty) return;

    Map<String, dynamic>? profile;
    String? error;
    try {
      profile = await ApiService.getUserProfile(widget.contactId);
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    }

    if (!mounted) return;

    if (profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error ?? 'Failed to load profile.')),
      );
      return;
    }

    final avatarUrl = profile['avatar_url']?.toString();
    final username = profile['username']?.toString() ?? widget.contactName;
    final email = profile['email']?.toString() ?? '';
    final aboutMe = profile['about_me']?.toString();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            UserAvatar(
              avatarUrl: avatarUrl,
              displayName: username,
              radius: 40,
            ),
            const SizedBox(height: 16),
            Text(username, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(email, style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                (aboutMe == null || aboutMe.isEmpty) ? 'No bio yet.' : aboutMe,
                style: const TextStyle(color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // Audio recording toggle method
  Future<void> _toggleRecording() async {
    if (!_isRecording) {
      await _audioService.startRecording();
      setState(() => _isRecording = true);
    } else {
      final path = await _audioService.stopRecording();
      setState(() => _isRecording = false);
      if (path != null) {
        await _uploadAndSendMedia(File(path), 'audio');
      }
    }
  }

  @override
  void dispose() {
    if (ActiveChatTracker.isChatActive(widget.chatId)) {
      ActiveChatTracker.setActiveChat(null);
    }
    SocketService.off('connect', _onConnect);
    SocketService.off('receive_message', _onReceiveMessage);
    SocketService.off('error_feedback', _onErrorFeedbackMarksFailed);
    SocketService.off('user_typing', _onUserTyping);
    SocketService.off('message_edited', _onMessageEdited);
    SocketService.off('message_deleted', _onMessageDeleted);
    SocketService.off('messages_read', _onMessagesRead);
    SocketService.off('error_feedback', _onErrorFeedback);
    _itemPositionsListener.itemPositions.removeListener(_handleItemPositionsChanged);
    _messageController.dispose();
    _typingTimer?.cancel();
    for (final timer in _pendingSendTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMuted = NotificationSettingsService.isChatMuted(widget.chatId);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.contactName, style: const TextStyle(fontSize: 16)),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) {
              if (value == 'mute') {
                NotificationSettingsService.toggleMuteChat(widget.chatId);
                final nowMuted = NotificationSettingsService.isChatMuted(widget.chatId);
                ApiService.setChatMuted(widget.chatId, nowMuted);
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(nowMuted ? 'Chat muted' : 'Chat unmuted')),
                );
              } else if (value == 'view_profile') {
                _viewProfile();
              } else if (value == 'remove_friend') {
                _confirmRemoveFriend();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'mute',
                child: Text(isMuted ? 'Unmute Notifications' : 'Mute Notifications'),
              ),
              const PopupMenuItem(
                value: 'view_profile',
                child: Text('View Profile'),
              ),
              const PopupMenuItem(
                value: 'remove_friend',
                child: Text('Remove Friend', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Message List View
          Expanded(
            child: Stack(
              children: [
                _isLoadingHistory
                    ? Center(child: CircularProgressIndicator(color: AppColors.primary))
                    : _messages.isEmpty
                        ? const Center(child: Text('Say hello and start the conversation!', style: TextStyle(color: AppColors.textSecondary)))
                        : ScrollablePositionedList.builder(
                            itemScrollController: _itemScrollController,
                            itemPositionsListener: _itemPositionsListener,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            // +1 for a trailing zero-height sentinel used to reliably
                            // jump to the true bottom (see _scrollToBottom / _jumpToInitialPosition).
                            itemCount: _messages.length + 1,
                            itemBuilder: (context, index) {
                              if (index == _messages.length) {
                                return const SizedBox.shrink();
                              }
                              final msg = _messages[index];
                              final bool isMe = _currentUserId != null && msg['sender_id'] == _currentUserId;
                              final bool isDeleted = msg['is_deleted'] ?? false;
                              final String status = msg['status'] ?? 'sent';
                              // A message that hasn't been confirmed by the server yet
                              // (still sending, or failed) has no real id — editing or
                              // deleting it doesn't make sense until it's confirmed.
                              final bool isConfirmed = status != 'sending' && status != 'failed';

                              return MessageBubble(
                                messageId: msg['id'] ?? '',
                                content: msg['content'] ?? '',
                                mediaUrl: msg['media_url'],
                                mediaType: msg['media_type'] ?? 'text',
                                isMe: isMe,
                                isDeleted: isDeleted,
                                timestamp: _formatTimestamp(msg['created_at']),
                                status: status,
                                isEdited: msg['is_edited'] ?? false,
                                replyTo: msg['reply_to'] is Map
                                    ? Map<String, dynamic>.from(msg['reply_to'] as Map)
                                    : null,
                                replyToSenderName: msg['reply_to'] is Map
                                    ? _replySenderLabel(Map<String, dynamic>.from(msg['reply_to'] as Map))
                                    : null,
                                onEdit: (isMe && !isDeleted && isConfirmed)
                                    ? () => _editMessage(msg['id'] ?? '', msg['content'] ?? '')
                                    : null,
                                onDelete: (isMe && !isDeleted && isConfirmed)
                                    ? () => _confirmDeleteMessage(msg['id'] ?? '')
                                    : null,
                                onRetry: (isMe && status == 'failed')
                                    ? () => _retryMessage(msg['_tempId'] as String)
                                    : null,
                                onReply: (isConfirmed && !isDeleted) ? () => _startReply(msg) : null,
                              );
                            },
                          ),
                if (_showJumpToLatestButton)
                  Positioned(
                    bottom: 12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Material(
                        color: Colors.white,
                        elevation: 3,
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () {
                            setState(() => _showJumpToLatestButton = false);
                            _scrollToBottom();
                          },
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.arrow_downward, size: 16, color: AppColors.primary),
                                SizedBox(width: 6),
                                Text(
                                  'More messages',
                                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SizeTransition(sizeFactor: animation, axisAlignment: -1, child: child),
            ),
            child: _isRemoteUserTyping
                ? const Padding(
                    key: ValueKey('typing'),
                    padding: EdgeInsets.only(top: 4),
                    child: TypingIndicatorBubble(),
                  )
                : const SizedBox.shrink(key: ValueKey('not_typing')),
          ),

          if (_replyingTo != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                border: Border(top: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Row(
                children: [
                  Container(width: 3, height: 32, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Replying to ${_replySenderLabel(_replyingTo!)}',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.primary),
                        ),
                        Text(
                          _replyPreviewText(_replyingTo!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: _cancelReply,
                  ),
                ],
              ),
            ),

          // Message Input Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            color: Colors.white,
            child: Row(
              children: [
                if (_isUploadingMedia)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                    ),
                  )
                else ...[
                  IconButton(
                    icon: Icon(Icons.photo, color: AppColors.primary),
                    onPressed: () => _pickAndSendMedia(ImageSource.gallery),
                    tooltip: 'Send from Gallery',
                  ),
                  IconButton(
                    icon: Icon(Icons.photo_camera, color: AppColors.primary),
                    onPressed: () => _pickAndSendMedia(ImageSource.camera),
                    tooltip: 'Take Photo or Video',
                  ),
                  IconButton(
                    icon: Icon(_isRecording ? Icons.stop : Icons.mic, color: _isRecording ? Colors.red : AppColors.primary),
                    onPressed: _toggleRecording,
                    tooltip: _isRecording ? 'Stop Recording' : 'Record Audio',
                  ),
                ],
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    onChanged: _handleTyping,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      border: InputBorder.none,
                      filled: false,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send, color: AppColors.primary),
                  onPressed: () => _sendMessage(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}