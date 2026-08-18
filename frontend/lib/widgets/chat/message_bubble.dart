import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../screens/media/full_screen_media_viewer.dart';
import '../../services/api_service.dart';
import '../../services/audio_service.dart';
import '../../services/video_thumbnail_service.dart';
import '../../theme/app_colors.dart';

class MessageBubble extends StatefulWidget {
  final String messageId;
  final String content;
  final String? mediaUrl;
  final String mediaType;
  final bool isMe;
  final bool isDeleted;
  final String timestamp;
  final String status; // 'sending', 'sent', 'delivered', 'read', 'failed'
  final bool isEdited;
  // Lightweight preview of the message this one is replying to, if any.
  // Expected keys: 'sender_id', 'content', 'media_type', 'is_deleted'.
  final Map<String, dynamic>? replyTo;
  final String? replyToSenderName;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onRetry;
  final VoidCallback? onReply;

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
    this.replyTo,
    this.replyToSenderName,
    this.onEdit,
    this.onDelete,
    this.onRetry,
    this.onReply,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  static const double _maxDrag = 64;
  static const double _triggerDrag = 48;

  double _dragExtent = 0;
  bool _dragging = false;

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (widget.onReply == null) return;
    setState(() {
      _dragging = true;
      _dragExtent = (_dragExtent + details.delta.dx).clamp(-_maxDrag, _maxDrag);
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (widget.onReply == null) return;
    if (_dragExtent.abs() >= _triggerDrag) {
      HapticFeedback.selectionClick();
      widget.onReply!();
    }
    setState(() {
      _dragging = false;
      _dragExtent = 0;
    });
  }

  void _showActionsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.mediaType == 'text' && widget.onEdit != null)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onEdit!();
                },
              ),
            if (widget.onDelete != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.error),
                title: const Text('Delete', style: TextStyle(color: AppColors.error)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onDelete!();
                },
              ),
          ],
        ),
      ),
    );
  }

  String _replyPreviewText(Map<String, dynamic> reply) {
    if (reply['is_deleted'] == true) return 'This message was deleted';
    final content = (reply['content'] ?? '').toString();
    if (content.isNotEmpty) return content;
    switch (reply['media_type']) {
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

  Widget _buildStatusIcon() {
    if (widget.status == 'sending') {
      return SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.grey.shade400),
      );
    }

    if (widget.status == 'failed') {
      return GestureDetector(
        onTap: widget.onRetry,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 14, color: AppColors.error),
            const SizedBox(width: 2),
            Text(
              'Failed · Retry',
              style: TextStyle(fontSize: 10, color: AppColors.error, fontWeight: FontWeight.w600, decoration: TextDecoration.underline),
            ),
          ],
        ),
      );
    }

    IconData icon;
    Color color = Colors.grey.shade400;

    if (widget.status == 'sent') {
      icon = Icons.check;
    } else if (widget.status == 'delivered') {
      icon = Icons.done_all;
    } else if (widget.status == 'read') {
      icon = Icons.done_all;
      color = Colors.blue.shade400; // Read indicator color
    } else {
      icon = Icons.check;
    }

    return Icon(icon, size: 16, color: color);
  }

  void _openFullScreen(BuildContext context) {
    Navigator.of(context).push(
      FullScreenMediaViewer.route(mediaUrl: widget.mediaUrl!, mediaType: widget.mediaType),
    );
  }

  Widget _buildMediaPreview(BuildContext context, bool isMe) {
    switch (widget.mediaType) {
      case 'audio':
        return _AudioBubble(url: widget.mediaUrl!, isMe: isMe);
      case 'video':
        return GestureDetector(
          onTap: () => _openFullScreen(context),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: _VideoThumbnail(url: widget.mediaUrl!),
          ),
        );
      case 'image':
      default:
        return GestureDetector(
          onTap: () => _openFullScreen(context),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              ApiService.mediaUrl(widget.mediaUrl!),
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
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMe = widget.isMe;
    final canShowActions = isMe && !widget.isDeleted && (widget.onEdit != null || widget.onDelete != null);
    final showReplyIcon = _dragExtent.abs() > 8;
    final replyIconOpacity = (_dragExtent.abs() / _triggerDrag).clamp(0.0, 1.0);

    return Stack(
      alignment: Alignment.center,
      children: [
        if (showReplyIcon)
          Align(
            alignment: _dragExtent > 0 ? Alignment.centerLeft : Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Opacity(
                opacity: replyIconOpacity,
                child: Icon(Icons.reply, color: AppColors.primary),
              ),
            ),
          ),
        GestureDetector(
          onHorizontalDragUpdate: _onHorizontalDragUpdate,
          onHorizontalDragEnd: _onHorizontalDragEnd,
          onLongPress: canShowActions ? () => _showActionsSheet(context) : null,
          child: AnimatedContainer(
            duration: _dragging ? Duration.zero : const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(_dragExtent, 0, 0),
            child: Align(
              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                decoration: BoxDecoration(
                  gradient: isMe
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.primary,
                            Color.lerp(AppColors.primary, Colors.black, 0.18)!,
                          ],
                        )
                      : null,
                  color: isMe ? null : Colors.white,
                  border: isMe ? null : Border.all(color: const Color(0xFFEDEDF2)),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isMe ? 18 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 18),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (isMe ? AppColors.primary : Colors.black).withValues(alpha: isMe ? 0.18 : 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.replyTo != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: (isMe ? Colors.white : AppColors.primary).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border(
                            left: BorderSide(color: isMe ? Colors.white70 : AppColors.primary, width: 3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.replyToSenderName ?? 'Message',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isMe ? Colors.white : AppColors.primary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _replyPreviewText(widget.replyTo!),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: isMe ? Colors.white70 : AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (widget.isDeleted)
                      Text(
                        'This message was deleted',
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: isMe ? Colors.white70 : AppColors.textSecondary,
                          fontSize: 15,
                        ),
                      )
                    else ...[
                      if (widget.mediaUrl != null && widget.mediaUrl!.isNotEmpty)
                        _buildMediaPreview(context, isMe),
                      if (widget.content.isNotEmpty) ...[
                        if (widget.mediaUrl != null) const SizedBox(height: 6),
                        Text(
                          widget.content,
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
                        if (widget.isEdited && !widget.isDeleted)
                          Text('(edited) ', style: TextStyle(fontSize: 10, color: isMe ? Colors.white70 : Colors.grey)),
                        Text(
                          widget.timestamp,
                          style: TextStyle(
                            fontSize: 10,
                            color: isMe ? Colors.white70 : AppColors.textSecondary,
                          ),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 4),
                          _buildStatusIcon(),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
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

class _VideoThumbnail extends StatefulWidget {
  final String url;

  const _VideoThumbnail({required this.url});

  @override
  State<_VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<_VideoThumbnail> {
  Uint8List? _thumbnail;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    final bytes = await VideoThumbnailService.getThumbnail(widget.url);
    if (!mounted) return;
    setState(() {
      _thumbnail = bytes;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        if (_thumbnail != null)
          Image.memory(
            _thumbnail!,
            height: 150,
            width: double.infinity,
            fit: BoxFit.cover,
          )
        else
          Container(
            height: 150,
            width: double.infinity,
            color: Colors.black12,
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : null,
          ),
        Container(
          decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
          padding: const EdgeInsets.all(8),
          child: const Icon(Icons.play_arrow, size: 32, color: Colors.white),
        ),
      ],
    );
  }
}