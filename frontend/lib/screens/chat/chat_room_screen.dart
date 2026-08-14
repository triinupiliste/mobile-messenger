import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../services/api_service.dart';
import '../../services/socket_service.dart';
import '../../services/audio_service.dart';
import '../../services/notification_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/chat/message_bubble.dart';

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
  
  final List<Map<String, dynamic>> _messages = [];
  bool _isRemoteUserTyping = false;
  Timer? _typingTimer;
  bool _isTyping = false;
  bool _isRecording = false;
  bool _isLoadingHistory = true;
  bool _isUploadingMedia = false;
  bool _showJumpToLatestButton = false;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();

    // 1. Join the specific chat room via socket
    SocketService.joinChat(widget.chatId);

    // Re-join whenever the socket (re)connects — e.g. after the app is backgrounded
    // and the connection drops — otherwise this screen stops receiving real-time
    // updates for its own sent messages until it's reopened.
    SocketService.socket.on('connect', (_) {
      SocketService.joinChat(widget.chatId);
    });

    // 2. Listen for incoming real-time socket events
    SocketService.socket.on('receive_message', (data) {
      if (data['chat_id'] == widget.chatId) {
        setState(() {
          _messages.add(Map<String, dynamic>.from(data));
        });
        _scrollToBottom();
      }
    });

    SocketService.socket.on('user_typing', (data) {
      if (data['chatId'] == widget.chatId) {
        setState(() {
          _isRemoteUserTyping = data['isTyping'];
        });
      }
    });

    SocketService.socket.on('message_edited', (data) {
      setState(() {
        final index = _messages.indexWhere((m) => m['id'] == data['id']);
        if (index != -1) {
          _messages[index]['content'] = data['content'];
          _messages[index]['is_edited'] = true;
        }
      });
    });

    SocketService.socket.on('message_deleted', (data) {
      setState(() {
        final index = _messages.indexWhere((m) => m['id'] == data['id']);
        if (index != -1) {
          _messages[index]['content'] = null;
          _messages[index]['media_url'] = null;
          _messages[index]['is_deleted'] = true;
        }
      });
    });

    // When the other participant reads this chat, mark my sent messages as 'read'
    // so the delivery ticks update in real time.
    SocketService.socket.on('messages_read', (data) {
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
    });

    SocketService.socket.on('error_feedback', (data) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(data['message']?.toString() ?? 'Something went wrong.')),
      );
    });

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
    return DateFormat('HH:mm').format(parsed.toLocal());
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

  void _sendMessage({String? mediaUrl, String mediaType = 'text'}) {
    final content = _messageController.text.trim();
    if (content.isEmpty && mediaUrl == null) return;

    SocketService.sendMessage(
      widget.chatId,
      content,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
    );

    _messageController.clear();
    if (_isTyping) {
      _isTyping = false;
      SocketService.sendTypingIndicator(widget.chatId, false);
    }
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
                leading: const Icon(Icons.photo, color: AppColors.primary),
                title: const Text('Photo'),
                onTap: () => Navigator.pop(context, 'image'),
              ),
              ListTile(
                leading: const Icon(Icons.videocam, color: AppColors.primary),
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
            CircleAvatar(
              radius: 40,
              backgroundColor: AppColors.primary.withOpacity(0.1),
              backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                  ? NetworkImage(avatarUrl)
                  : null,
              child: (avatarUrl == null || avatarUrl.isEmpty)
                  ? const Icon(Icons.person, size: 40, color: AppColors.primary)
                  : null,
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
    _itemPositionsListener.itemPositions.removeListener(_handleItemPositionsChanged);
    _messageController.dispose();
    _typingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMuted = NotificationSettingsService.isChatMuted(widget.chatId);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(widget.contactName, style: const TextStyle(fontSize: 16)),
            if (_isRemoteUserTyping)
              const Text('typing...', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.white70)),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) {
              if (value == 'mute') {
                NotificationSettingsService.toggleMuteChat(widget.chatId);
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(NotificationSettingsService.isChatMuted(widget.chatId) ? 'Chat muted' : 'Chat unmuted')),
                );
              } else if (value == 'view_profile') {
                _viewProfile();
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
                    ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
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

                              return MessageBubble(
                                messageId: msg['id'] ?? '',
                                content: msg['content'] ?? '',
                                mediaUrl: msg['media_url'],
                                mediaType: msg['media_type'] ?? 'text',
                                isMe: isMe,
                                isDeleted: isDeleted,
                                timestamp: _formatTimestamp(msg['created_at']),
                                status: msg['status'] ?? 'sent',
                                isEdited: msg['is_edited'] ?? false,
                                onEdit: (isMe && !isDeleted)
                                    ? () => _editMessage(msg['id'] ?? '', msg['content'] ?? '')
                                    : null,
                                onDelete: (isMe && !isDeleted)
                                    ? () => _confirmDeleteMessage(msg['id'] ?? '')
                                    : null,
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
                          child: const Padding(
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

          // Message Input Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            color: Colors.white,
            child: Row(
              children: [
                if (_isUploadingMedia)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                    ),
                  )
                else ...[
                  IconButton(
                    icon: const Icon(Icons.photo, color: AppColors.primary),
                    onPressed: () => _pickAndSendMedia(ImageSource.gallery),
                    tooltip: 'Send from Gallery',
                  ),
                  IconButton(
                    icon: const Icon(Icons.photo_camera, color: AppColors.primary),
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
                  icon: const Icon(Icons.send, color: AppColors.primary),
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