import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../constants/socket_events.dart';
import '../../providers/chat_provider.dart';
import '../../providers/message_provider.dart';
import '../../services/api_service.dart';
import '../../services/socket_service.dart';
import '../../services/audio_service.dart';
import '../../services/notification_service.dart';
import '../../services/push_notification_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/chat/message_bubble.dart';
import '../../widgets/chat/typing_indicator_bubble.dart';
import '../../widgets/common/user_avatar.dart';
import '../home/home_screen.dart';

// Thin wrapper that scopes a fresh MessageProvider to this specific chat
// room (created here, not registered globally in main.dart) — message state
// is only ever needed while this one screen is open, so it's created when
// the screen opens and disposed automatically when it closes.
class ChatRoomScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MessageProvider(chatId)..init(),
      child: _ChatRoomView(chatId: chatId, contactId: contactId, contactName: contactName),
    );
  }
}

class _ChatRoomView extends StatefulWidget {
  final String chatId;
  final String contactId;
  final String contactName;

  const _ChatRoomView({
    required this.chatId,
    required this.contactId,
    required this.contactName,
  });

  @override
  State<_ChatRoomView> createState() => _ChatRoomViewState();
}

class _ChatRoomViewState extends State<_ChatRoomView> {
  final TextEditingController _messageController = TextEditingController();
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener = ItemPositionsListener.create();
  final AudioService _audioService = AudioService();

  late final MessageProvider _messageProvider;
  int _lastMessageCount = 0;
  bool _lastLoadingHistory = true;

  bool _isRecording = false;
  bool _isUploadingMedia = false;
  bool _showJumpToLatestButton = false;
  Map<String, dynamic>? _replyingTo;

  // Stored so dispose() can unregister exactly this callback — without this,
  // reopening the same chat repeatedly stacks duplicate listeners on the
  // shared socket singleton, which stops new events from reliably reaching
  // the currently-visible screen (an earlier, already-disposed listener can
  // throw and prevent later listeners for the same event from running).
  late final void Function(dynamic) _onErrorFeedback;
  // Same reasoning as _onErrorFeedback: stored so dispose() removes exactly
  // this listener rather than leaking one on the shared socket singleton.
  late final void Function(dynamic) _onFriendRemoved;

  @override
  void initState() {
    super.initState();

    _messageProvider = context.read<MessageProvider>();
    _lastMessageCount = _messageProvider.messages.length;
    _lastLoadingHistory = _messageProvider.isLoadingHistory;
    _messageProvider.addListener(_onMessagesChanged);

    // Mark this chat as the one currently on screen, so a foreground push
    // notification for it can be suppressed (already visible live here).
    ActiveChatTracker.setActiveChat(widget.chatId);

    // Whether opened via a notification tap or directly through the app, its
    // messages are read the moment this screen is on screen — clear any
    // pending tray notification for it instead of leaving it lingering.
    PushNotificationService.cancelForChat(widget.chatId);

    // This is a UI-only concern (showing a SnackBar), so it stays registered
    // directly by the screen rather than living in MessageProvider.
    _onErrorFeedback = (data) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(data['message']?.toString() ?? 'Something went wrong.')),
      );
    };
    SocketService.on(SocketEvents.errorFeedback, _onErrorFeedback);

    // If the other person removes us as a friend while we're sitting in
    // this very chat, don't leave us looking at a conversation that no
    // longer exists for us — bounce back to the chat list immediately.
    _onFriendRemoved = (data) {
      if (!mounted) return;
      final removedChatId = data['chatId']?.toString();
      if (removedChatId != widget.chatId) return;
      // Capture the messenger before popping — once this route is gone,
      // `context` here is no longer safely usable to look one up.
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).popUntil((route) => route.isFirst);
      HomeScreen.homeKey.currentState?.switchToChatsTab();
      messenger.showSnackBar(
        SnackBar(content: Text('${widget.contactName} removed you as a friend.')),
      );
    };
    SocketService.on(SocketEvents.friendRemoved, _onFriendRemoved);

    // Track which messages are actually on screen so we can show a "more
    // messages" pill whenever there's an unread message hidden below the fold.
    _itemPositionsListener.itemPositions.addListener(_handleItemPositionsChanged);
  }

  // Reacts to MessageProvider changes with the imperative, UI-only side
  // effects that used to live directly inside the socket listeners: jumping
  // to the first unread message once history finishes loading, auto-scrolling
  // to the bottom when a new message is appended, and recomputing whether
  // the "jump to latest" pill should show.
  void _onMessagesChanged() {
    final isLoadingHistory = _messageProvider.isLoadingHistory;
    if (_lastLoadingHistory && !isLoadingHistory) {
      _jumpToInitialPosition();
    }
    _lastLoadingHistory = isLoadingHistory;

    final messageCount = _messageProvider.messages.length;
    if (messageCount > _lastMessageCount) {
      _scrollToBottom();
    }
    _lastMessageCount = messageCount;

    _handleItemPositionsChanged();
  }

  void _handleItemPositionsChanged() {
    final messages = _messageProvider.messages;
    if (messages.isEmpty) return;
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    final lastVisibleIndex = positions.map((p) => p.index).reduce((a, b) => a > b ? a : b);

    // Only show the pill when an unread message from the other participant is
    // still hidden below the current viewport — not just whenever we've
    // scrolled away from the very bottom. Once a message has been read
    // (locally, or already marked read in a previous visit to this chat),
    // it no longer counts, so the pill won't reappear for old, read history.
    final hasUnreadBelow = messages.asMap().entries.any((entry) =>
        entry.key > lastVisibleIndex &&
        entry.value['sender_id'] != _messageProvider.currentUserId &&
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

  // Jumps straight to the first unread message (from the other participant) so the
  // user lands right where they left off, instead of always landing at the bottom.
  // If everything is already read, it lands on the last message like normal.
  void _jumpToInitialPosition() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final messages = _messageProvider.messages;
      if (!_itemScrollController.isAttached || messages.isEmpty) return;

      final firstUnreadIndex = messages.indexWhere((m) =>
          m['sender_id'] != _messageProvider.currentUserId &&
          m['status'] != 'read' &&
          m['is_deleted'] != true);

      if (firstUnreadIndex == -1) {
        // The sentinel item (index == messages.length) has ~zero height, so
        // aligning its top edge to the bottom of the viewport (alignment 1.0)
        // is equivalent to flushing the real last message against the bottom.
        _itemScrollController.jumpTo(index: messages.length, alignment: 1.0);
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
  // We target the sentinel item (index == messages.length, ~zero height)
  // rather than the last message itself: alignment positions an item's TOP
  // edge, so aligning the real last message's top to the viewport's bottom
  // (alignment 1.0) would push almost the whole bubble off-screen. Aligning
  // the near-zero-height sentinel's top to the bottom instead flushes the
  // real content's bottom edge against the viewport's bottom, as intended.
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final messages = _messageProvider.messages;
      if (!_itemScrollController.isAttached || messages.isEmpty) return;
      _itemScrollController.jumpTo(index: messages.length, alignment: 1.0);
    });
  }

  void _handleTyping(String text) {
    _messageProvider.handleTyping();
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
    return replyTo['sender_id'] == _messageProvider.currentUserId ? 'You' : widget.contactName;
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

    _messageProvider.sendMessage(
      content,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      replyingTo: _replyingTo,
    );

    setState(() => _replyingTo = null);
    _messageController.clear();
  }

  // Re-sends a message that previously failed (e.g. connection dropped, or
  // the server rejected it), reusing the same tempId so the retried send
  // still replaces this same bubble once confirmed.
  void _retryMessage(String tempId) {
    _messageProvider.retryMessage(tempId);
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

    // The dialog's TextField held focus while open; without explicitly
    // unfocusing, focus bounces back to the chat's message input field once
    // the dialog closes, popping the keyboard back up.
    FocusManager.instance.primaryFocus?.unfocus();

    if (newContent == null || newContent.isEmpty || newContent == currentContent) return;

    _messageProvider.editMessage(messageId, newContent);
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

    // Same as _editMessage: prevent focus from bouncing back to the message
    // input field and reopening the keyboard once this dialog closes.
    FocusManager.instance.primaryFocus?.unfocus();

    if (confirmed != true) return;

    _messageProvider.deleteMessage(messageId);
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
        // Cap recording length as a sanity bound on upload size/time — actual
        // compression now happens server-side (see
        // backend/src/utils/video.util.ts) using ffmpeg, since the on-device
        // video_compress plugin proved unreliable (silent hangs, broken
        // output paths on some devices/OS versions). A minute of typical
        // phone video comfortably fits within the server's raw upload limit.
        pickedFile = await picker.pickVideo(
          source: source,
          maxDuration: const Duration(minutes: 1),
        );
      }
    }

    if (pickedFile == null) return;

    try {
      final file = File(pickedFile.path);
      final fileSizeInMB = await file.length() / (1024 * 1024);

      // Videos are compressed server-side after upload, so they're only
      // rejected here if they're too large to even attempt uploading (the
      // server enforces the real 20MB-after-compression limit and returns a
      // clear error if a clip still doesn't fit). Non-video media isn't
      // compressed, so the 20MB limit is enforced directly on-device.
      if (mediaKind == 'video' ? fileSizeInMB > 150 : fileSizeInMB > 20) {
        if (mounted) {
          final message = mediaKind == 'video'
              ? 'This video is too large to send. Try a shorter clip.'
              : 'Media file size exceeds the 20MB limit.';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        }
        return;
      }

      await _uploadAndSendMedia(file, mediaKind);
    } catch (e) {
      // Surface anything unexpected (e.g. a picker/file-system error) instead
      // of leaving the user staring at a picker that closed with nothing
      // visibly happening.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to prepare $mediaKind: ${e.toString().replaceFirst('Exception: ', '')}')),
        );
      }
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
      // Land back on the Chats tab specifically (now missing this chat),
      // rather than just popping to whichever tab happened to be active
      // when this chat was opened (e.g. Search or Invites).
      Navigator.popUntil(context, (route) => route.isFirst);
      HomeScreen.homeKey.currentState?.switchToChatsTab();
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
    _messageProvider.removeListener(_onMessagesChanged);
    SocketService.off(SocketEvents.errorFeedback, _onErrorFeedback);
    SocketService.off(SocketEvents.friendRemoved, _onFriendRemoved);
    _itemPositionsListener.itemPositions.removeListener(_handleItemPositionsChanged);
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messageProvider = context.watch<MessageProvider>();
    final messages = messageProvider.messages;
    final isLoadingHistory = messageProvider.isLoadingHistory;
    final isRemoteUserTyping = messageProvider.isRemoteUserTyping;
    final currentUserId = messageProvider.currentUserId;
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
                isLoadingHistory
                    ? Center(child: CircularProgressIndicator(color: AppColors.primary))
                    : messages.isEmpty
                        ? const Center(child: Text('Say hello and start the conversation!', style: TextStyle(color: AppColors.textSecondary)))
                        : ScrollablePositionedList.builder(
                            itemScrollController: _itemScrollController,
                            itemPositionsListener: _itemPositionsListener,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            // +1 for a trailing zero-height sentinel used to reliably
                            // jump to the true bottom (see _scrollToBottom / _jumpToInitialPosition).
                            itemCount: messages.length + 1,
                            itemBuilder: (context, index) {
                              if (index == messages.length) {
                                return const SizedBox.shrink();
                              }
                              final msg = messages[index];
                              final bool isMe = currentUserId != null && msg['sender_id'] == currentUserId;
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
              child: SizeTransition(sizeFactor: animation, alignment: Alignment(-1.0, -1.0), child: child),
            ),
            child: isRemoteUserTyping
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
