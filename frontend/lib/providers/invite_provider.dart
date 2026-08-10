import 'package:flutter/material.dart';
import '../models/invite_model.dart';

class InviteProvider with ChangeNotifier {
  // Mock list for pending invites; can be replaced with real API calls
  final List<InviteModel> _pendingInvites = [
    InviteModel(
      inviteId: '1',
      senderId: 'user_123',
      senderUsername: 'alex_dev',
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    ),
  ];

  List<InviteModel> get pendingInvites => _pendingInvites;

  Future<void> respondToInvite(String inviteId, bool accept) async {
    _pendingInvites.removeWhere((invite) => invite.inviteId == inviteId);
    notifyListeners();
    // Call backend API to accept/decline invite here
  }
}