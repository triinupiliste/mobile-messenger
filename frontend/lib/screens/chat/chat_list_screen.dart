import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/user_avatar.dart';
import 'chat_room_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  bool _showArchived = false;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ChatProvider>(context, listen: false).fetchChats();
    });
    _loadCurrentUserId();
  }

  Future<void> _loadCurrentUserId() async {
    try {
      final profile = await ApiService.getProfile();
      if (!mounted) return;
      setState(() {
        _currentUserId = profile['id']?.toString() ?? profile['user_id']?.toString();
      });
    } catch (_) {
      // Ignore; falls back to showing messages without the 'You:' prefix.
    }
  }

  String? _mediaPreviewLabel(String? mediaType) {
    switch (mediaType) {
      case 'image':
        return 'Sent a photo';
      case 'video':
        return 'Sent a video';
      case 'audio':
        return 'Sent a voice message';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_showArchived ? 'Archived Messages' : 'Messages'),
        actions: [
          IconButton(
            icon: Icon(_showArchived ? Icons.archive : Icons.archive_outlined),
            tooltip: 'Toggle Archived Chats',
            onPressed: () {
              setState(() {
                _showArchived = !_showArchived;
              });
            },
          ),
        ],
      ),
      body: Consumer<ChatProvider>(
        builder: (context, chatProvider, child) {
          if (chatProvider.isLoading) {
            return Center(child: CircularProgressIndicator(color: AppColors.primary));
          }

          final filteredChats = chatProvider.chats.where((chat) {
            return _showArchived ? chat.isArchived : !chat.isArchived;
          }).toList();

          if (filteredChats.isEmpty) {
            return Center(
              child: Text(
                _showArchived ? 'No archived chats' : 'No conversations yet.\nSearch for contacts to start chatting!',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 16),
              ),
            );
          }

          return ListView.builder(
            itemCount: filteredChats.length,
            itemBuilder: (context, index) {
              final chat = filteredChats[index];
              final chatId = chat.chatId;
              final contactName = chat.contactName;
              final isArchived = chat.isArchived;

              final isFromMe = _currentUserId != null && chat.lastMessageSenderId == _currentUserId;
              // Only bold the preview for unread messages the *other* person sent.
              final hasUnread = chat.unreadCount > 0 && !isFromMe;

              final hasTextContent = chat.lastMessage != null && chat.lastMessage!.isNotEmpty;
              final mediaLabel = _mediaPreviewLabel(chat.lastMessageType);

              final String previewText;
              if (!hasTextContent && mediaLabel == null) {
                previewText = 'Start a conversation';
              } else {
                final body = hasTextContent ? chat.lastMessage! : mediaLabel!;
                previewText = isFromMe ? 'You: $body' : body;
              }

              return Dismissible(
                key: Key(chatId),
                background: Container(
                  color: AppColors.warning,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Icon(isArchived ? Icons.unarchive : Icons.archive, color: AppColors.onPrimary),
                ),
                secondaryBackground: Container(
                  color: AppColors.error,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Icon(Icons.delete, color: AppColors.onPrimary),
                ),
                confirmDismiss: (direction) async {
                  final messenger = ScaffoldMessenger.of(context);
                  messenger.clearSnackBars();

                  if (direction == DismissDirection.startToEnd) {
                    chatProvider.toggleArchiveChat(chatId);
                    final controller = messenger.showSnackBar(
                      SnackBar(
                        content: Text(isArchived ? 'Chat unarchived' : 'Chat archived'),
                        duration: const Duration(seconds: 5),
                        action: SnackBarAction(
                          label: 'Undo',
                          onPressed: () => chatProvider.toggleArchiveChat(chatId),
                        ),
                      ),
                    );
                    Future.delayed(const Duration(seconds: 5), controller.close);
                    return true;
                  }

                  chatProvider.deleteChat(chatId);
                  final controller = messenger.showSnackBar(
                    SnackBar(
                      content: const Text('Chat deleted'),
                      duration: const Duration(seconds: 5),
                      action: SnackBarAction(
                        label: 'Undo',
                        onPressed: () => chatProvider.undoDeleteChat(),
                      ),
                    ),
                  );
                  Future.delayed(const Duration(seconds: 5), controller.close);
                  return true;
                },
                child: ListTile(
                  leading: UserAvatar(
                    avatarUrl: chat.contactAvatar,
                    displayName: contactName,
                  ),
                  title: Text(contactName, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  subtitle: Text(
                    previewText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: hasUnread ? AppColors.textPrimary : AppColors.textSecondary,
                      fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasUnread)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          constraints: const BoxConstraints(minWidth: 22),
                          child: Text(
                            chat.unreadCount > 99 ? '99+' : '${chat.unreadCount}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.onPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right, size: 18, color: AppColors.textSecondary),
                    ],
                  ),
                  onTap: () async {
                    final chatProv = context.read<ChatProvider>();

                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatRoomScreen(
                          chatId: chatId,
                          contactId: chat.contactId,
                          contactName: contactName,
                        ),
                      ),
                    );
                    
                    if (!mounted) return;
                    chatProv.fetchChats();
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}