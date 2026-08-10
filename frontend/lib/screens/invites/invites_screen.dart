import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class InvitesScreen extends StatefulWidget {
  const InvitesScreen({super.key});

  @override
  State<InvitesScreen> createState() => _InvitesScreenState();
}

class _InvitesScreenState extends State<InvitesScreen> {
  // Mock pending invites list (Will be populated via ApiService / InviteProvider)
  final List<Map<String, dynamic>> _pendingInvites = [
    {'invite_id': '1', 'sender_username': 'alex_dev', 'created_at': '2026-08-10'},
    {'invite_id': '2', 'sender_username': 'sarah_chat', 'created_at': '2026-08-09'},
  ];

  void _respondToInvite(String inviteId, bool accept) {
    setState(() {
      _pendingInvites.removeWhere((invite) => invite['invite_id'] == inviteId);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(accept ? 'Invitation accepted!' : 'Invitation declined.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat Invitations')),
      body: _pendingInvites.isEmpty
          ? const Center(
              child: Text(
                'No pending invitations.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
              ),
            )
          : ListView.builder(
              itemCount: _pendingInvites.length,
              itemBuilder: (context, index) {
                final invite = _pendingInvites[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary.withOpacity(0.2),
                      child: Text(
                        invite['sender_username'][0].toUpperCase(),
                        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(invite['sender_username'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Wants to start a conversation', style: TextStyle(color: AppColors.textSecondary)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.check_circle, color: Colors.green, size: 28),
                          onPressed: () => _respondToInvite(invite['invite_id'], true),
                          tooltip: 'Accept',
                        ),
                        IconButton(
                          icon: const Icon(Icons.cancel, color: Colors.red, size: 28),
                          onPressed: () => _respondToInvite(invite['invite_id'], false),
                          tooltip: 'Decline',
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}