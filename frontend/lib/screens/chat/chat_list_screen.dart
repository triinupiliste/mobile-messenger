import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/chat_provider.dart';
import '../../theme/app_colors.dart';
import 'chat_room_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ChatProvider>(context, listen: false).fetchChats();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
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
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
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
              final lastMessage = chat.lastMessage ?? 'Start a conversation';
              final isArchived = chat.isArchived;

              return Dismissible(
                key: Key(chatId),
                background: Container(
                  color: Colors.amber.shade700,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Icon(isArchived ? Icons.unarchive : Icons.archive, color: Colors.white),
                ),
                secondaryBackground: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                confirmDismiss: (direction) async {
                  if (direction == DismissDirection.startToEnd) {
                    chatProvider.toggleArchiveChat(chatId);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(isArchived ? 'Chat unarchived' : 'Chat archived')),
                    );
                    return false;
                  }
                  return false;
                },
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withOpacity(0.2),
                    child: Text(
                      contactName.isNotEmpty ? contactName[0].toUpperCase() : '?',
                      style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(contactName, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  subtitle: Text(lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textSecondary)),
                  trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatRoomScreen(chatId: chatId, contactName: contactName),
                      ),
                    );
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