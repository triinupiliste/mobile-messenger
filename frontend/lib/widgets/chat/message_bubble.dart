import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class MessageBubble extends StatelessWidget {
  final String messageId;
  final String content;
  final String? mediaUrl;
  final String mediaType;
  final bool isMe;
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
            if (mediaUrl != null && mediaUrl!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(mediaUrl!, height: 150, width: double.infinity, fit: BoxFit.cover),
              ),
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
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isEdited)
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
                if (isMe) ...[
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