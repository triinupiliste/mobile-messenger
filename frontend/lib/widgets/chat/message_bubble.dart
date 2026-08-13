import 'package:flutter/material.dart';
import '../../services/audio_service.dart';
import '../../theme/app_colors.dart';

class MessageBubble extends StatelessWidget {
  final String messageId;
  final String content;
  final String? mediaUrl;
  final String mediaType;
  final bool isMe;
  final bool isDeleted;
  final String timestamp;
  final String status; // 'sent', 'delivered', 'read'
  final bool isEdited;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const MessageBubble({
    super.key,
    required this.messageId,
    required this.content,
    this.mediaUrl,
    required this.mediaType,
    required this.isMe,
    this.isDeleted = false,
    required this.timestamp,
    required this.status,
    required this.isEdited,
    this.onEdit,
    this.onDelete,
  });

  Widget _buildStatusIcon() {
    IconData icon;
    Color color = Colors.grey.shade400;

    if (status == 'sent') {
      icon = Icons.check;
    } else if (status == 'delivered') {
      icon = Icons.done_all;
    } else if (status == 'read') {
      icon = Icons.done_all;
      color = Colors.blue.shade400; // Read indicator color
    } else {
      icon = Icons.error_outline;
      color = AppColors.error; // Failed delivery feedback
    }

    return Icon(icon, size: 16, color: color);
  }

  Widget _buildMediaPreview(bool isMe) {
    switch (mediaType) {
      case 'audio':
        return _AudioBubble(url: mediaUrl!, isMe: isMe);
      case 'video':
        return Container(
          height: 150,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.black12,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Center(
            child: Icon(Icons.videocam, size: 40, color: Colors.black45),
          ),
        );
      case 'image':
      default:
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            mediaUrl!,
            height: 150,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              height: 150,
              width: double.infinity,
              color: Colors.black12,
              child: const Center(
                child: Icon(Icons.broken_image, color: Colors.black45),
              ),
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isMe ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isDeleted)
              Text(
                'This message was deleted',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: isMe ? Colors.white70 : AppColors.textSecondary,
                  fontSize: 15,
                ),
              )
            else ...[
              if (mediaUrl != null && mediaUrl!.isNotEmpty)
                _buildMediaPreview(isMe),
              if (content.isNotEmpty) ...[
                if (mediaUrl != null) const SizedBox(height: 6),
                Text(
                  content,
                  style: TextStyle(
                    color: isMe ? Colors.white : AppColors.textPrimary,
                    fontSize: 15,
                  ),
                ),
              ],
            ],
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isEdited && !isDeleted)
                  Text('(edited) ', style: TextStyle(fontSize: 10, color: isMe ? Colors.white70 : Colors.grey)),
                Text(
                  timestamp,
                  style: TextStyle(
                    fontSize: 10,
                    color: isMe ? Colors.white70 : AppColors.textSecondary,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  _buildStatusIcon(),
                ],
                if (isMe && !isDeleted) ...[
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.more_vert, size: 14, color: isMe ? Colors.white70 : Colors.grey),
                    onSelected: (value) {
                      if (value == 'edit' && onEdit != null) onEdit!();
                      if (value == 'delete' && onDelete != null) onDelete!();
                    },
                    itemBuilder: (context) => [
                      if (mediaType == 'text') const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      const PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ]
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioBubble extends StatefulWidget {
  final String url;
  final bool isMe;

  const _AudioBubble({required this.url, required this.isMe});

  @override
  State<_AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<_AudioBubble> {
  final AudioService _audioService = AudioService();
  bool _isPlaying = false;

  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      await _audioService.stopAudio();
      setState(() => _isPlaying = false);
    } else {
      setState(() => _isPlaying = true);
      await _audioService.playAudio(widget.url);
    }
  }

  @override
  void dispose() {
    _audioService.stopAudio();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isMe ? Colors.white : AppColors.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, color: color, size: 32),
          onPressed: _togglePlayback,
        ),
        const SizedBox(width: 8),
        Text(
          'Voice message',
          style: TextStyle(color: widget.isMe ? Colors.white : AppColors.textPrimary, fontSize: 14),
        ),
      ],
    );
  }
}