import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/invite_provider.dart';
import '../../theme/app_colors.dart';

class InvitesScreen extends StatefulWidget {
  // When true (e.g. opened by tapping an invite push notification), this
  // screen marks incoming invites as seen as soon as it loads, instead of
  // relying on the bottom-nav tap handler (which only runs for the
  // persistent IndexedStack-embedded instance).
  final bool markSeenOnOpen;

  const InvitesScreen({super.key, this.markSeenOnOpen = false});

  @override
  State<InvitesScreen> createState() => InvitesScreenState();
}

class InvitesScreenState extends State<InvitesScreen> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await context.read<InviteProvider>().fetchInvites();
    if (widget.markSeenOnOpen && mounted) {
      context.read<InviteProvider>().markIncomingSeen();
    }
  }

  Future<void> refresh() => context.read<InviteProvider>().fetchInvites();

  Future<void> _respond(String inviteId, String status) async {
    try {
      await context.read<InviteProvider>().respondToInvite(inviteId, status);
      if (status == 'accepted' && mounted) {
        // A new chat was created on the backend; refresh the chat list so it appears immediately.
        context.read<ChatProvider>().fetchChats();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invitation $status successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inviteProvider = context.watch<InviteProvider>();
    final incoming = inviteProvider.incoming;
    final outgoing = inviteProvider.outgoing;
    final isLoading = inviteProvider.isLoading && incoming.isEmpty && outgoing.isEmpty;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          title: const Text('Chat Invitations',
              style: TextStyle(color: Colors.white)),
          iconTheme: const IconThemeData(color: Colors.white),
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            tabs: [
              Tab(text: 'Incoming'),
              Tab(text: 'Outgoing'),
            ],
          ),
        ),
        body: isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary))
            : TabBarView(
                children: [
                  // Incoming Tab
                  incoming.isEmpty
                      ? const Center(
                          child: Text('No incoming invitations',
                              style: TextStyle(color: AppColors.textSecondary)))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: incoming.length,
                          itemBuilder: (context, index) {
                            final invite = incoming[index];
                            final sender = invite['sender'] ?? {};
                            final senderAvatar = sender['avatar_url']?.toString();
                            return Card(
                              color: AppColors.surface,
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.primary,
                                  backgroundImage: (senderAvatar != null && senderAvatar.isNotEmpty)
                                      ? NetworkImage(senderAvatar)
                                      : null,
                                  child: (senderAvatar == null || senderAvatar.isEmpty)
                                      ? const Icon(Icons.person, color: Colors.white)
                                      : null,
                                ),
                                title: Text(sender['username'] ?? 'User',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary)),
                                subtitle: Text(sender['email'] ?? '',
                                    style: const TextStyle(
                                        color: AppColors.textSecondary)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.check,
                                          color: Colors.green),
                                      onPressed: () => _respond(
                                          invite['id'] ?? invite['_id'],
                                          'accepted'),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close,
                                          color: AppColors.error),
                                      onPressed: () => _respond(
                                          invite['id'] ?? invite['_id'],
                                          'declined'),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                  // Outgoing Tab
                  outgoing.isEmpty
                      ? const Center(
                          child: Text('No outgoing invitations',
                              style: TextStyle(color: AppColors.textSecondary)))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: outgoing.length,
                          itemBuilder: (context, index) {
                            final invite = outgoing[index];
                            final recipient = invite['recipient'] ?? {};
                            final recipientAvatar = recipient['avatar_url']?.toString();
                            return Card(
                              color: AppColors.surface,
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.textSecondary,
                                  backgroundImage: (recipientAvatar != null && recipientAvatar.isNotEmpty)
                                      ? NetworkImage(recipientAvatar)
                                      : null,
                                  child: (recipientAvatar == null || recipientAvatar.isEmpty)
                                      ? const Icon(Icons.person, color: Colors.white)
                                      : null,
                                ),
                                title: Text(recipient['username'] ?? 'User',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary)),
                                subtitle: Text(recipient['email'] ?? '',
                                    style: const TextStyle(
                                        color: AppColors.textSecondary)),
                                trailing: Chip(
                                  label: Text(
                                      (invite['status'] ?? 'pending')
                                          .toString(),
                                      style: TextStyle(
                                          fontSize: 12, color: Colors.white)),
                                  backgroundColor: AppColors.secondary,
                                ),
                              ),
                            );
                          },
                        ),
                ],
              ),
      ),
    );
  }
}
