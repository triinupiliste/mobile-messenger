import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/socket_service.dart';
import '../../services/audio_service.dart';
import '../../services/notification_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/chat/message_bubble.dart';

class ChatRoomScreen extends StatefulWidget {
  final String chatId;
  final String contactName;

  const ChatRoomScreen({
    super.key,
    required this.chatId,
    required this.contactName,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AudioService _audioService = AudioService();
  
  final List<Map<String, dynamic>> _messages = [];
  bool _isRemoteUserTyping = false;
  Timer? _typingTimer;
  bool _isTyping = false;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    
    // 1. Join the specific chat room via socket
    SocketService.joinChat(widget.chatId);

    // 2. Listen for incoming real-time socket events
    SocketService.socket.on('receive_message', (data) {
      if (data['chat_id'] == widget.chatId) {
        setState(() {
          _messages.add(data);
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
        final index = _messages.indexWhere((m) => m['message_id'] == data['message_id']);
        if (index != -1) {
          _messages[index]['content'] = data['content'];
          _messages[index]['is_edited'] = true;
        }
      });
    });

    SocketService.socket.on('message_deleted', (data) {
      setState(() {
        _messages.removeWhere((m) => m['message_id'] == data['message_id']);
      });
    });
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
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

  Future<void> _pickAndSendMedia(String type) async {
    final picker = ImagePicker();
    XFile? pickedFile;

    if (type == 'image') {
      pickedFile = await picker.pickImage(source: ImageSource.gallery);
    } else if (type == 'video') {
      pickedFile = await picker.pickVideo(source: ImageSource.gallery);
    }

    if (pickedFile != null) {
      final file = File(pickedFile.path);
      final fileSizeInMB = await file.length() / (1024 * 1024);

      if (fileSizeInMB > 20) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Media file size exceeds the 20MB limit.')),
        );
        return;
      }

      _sendMessage(mediaUrl: file.path, mediaType: type);
    }
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
        _sendMessage(mediaUrl: path, mediaType: 'audio');
      }
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
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
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'mute',
                child: Text(isMuted ? 'Unmute Notifications' : 'Mute Notifications'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Message List View
          Expanded(
            child: _messages.isEmpty
                ? const Center(child: Text('Say hello and start the conversation!', style: TextStyle(color: AppColors.textSecondary)))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final bool isMe = msg['is_me'] ?? true; 

                      return MessageBubble(
                        messageId: msg['message_id'] ?? '',
                        content: msg['content'] ?? '',
                        mediaUrl: msg['media_url'],
                        mediaType: msg['media_type'] ?? 'text',
                        isMe: isMe,
                        timestamp: 'Just now',
                        status: msg['status'] ?? 'sent',
                        isEdited: msg['is_edited'] ?? false,
                        onDelete: () {
                          SocketService.socket.emit('delete_message', {
                            'messageId': msg['message_id'],
                            'chatId': widget.chatId,
                          });
                        },
                      );
                    },
                  ),
          ),

          // Message Input Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            color: Colors.white,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.image, color: AppColors.primary),
                  onPressed: () => _pickAndSendMedia('image'),
                  tooltip: 'Send Image',
                ),
                IconButton(
                  icon: const Icon(Icons.videocam, color: AppColors.primary),
                  onPressed: () => _pickAndSendMedia('video'),
                  tooltip: 'Send Video',
                ),
                IconButton(
                  icon: Icon(_isRecording ? Icons.stop : Icons.mic, color: _isRecording ? Colors.red : AppColors.primary),
                  onPressed: _toggleRecording,
                  tooltip: _isRecording ? 'Stop Recording' : 'Record Audio',
                ),
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