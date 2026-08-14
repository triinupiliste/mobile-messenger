import 'package:flutter/material.dart';
import '../services/api_service.dart';

class InviteProvider with ChangeNotifier {
  List<dynamic> _incoming = [];
  List<dynamic> _outgoing = [];
  bool _isLoading = false;

  // Incoming invite ids the user has already looked at (i.e. had the Invites
  // tab open since they arrived). Drives the badge on the bottom nav icon.
  final Set<String> _seenInviteIds = {};

  List<dynamic> get incoming => _incoming;
  List<dynamic> get outgoing => _outgoing;
  bool get isLoading => _isLoading;

  int get unseenCount =>
      _incoming.where((invite) => !_seenInviteIds.contains(_inviteId(invite))).length;

  String _inviteId(dynamic invite) => (invite['id'] ?? invite['_id'] ?? '').toString();

  Future<void> fetchInvites() async {
    _isLoading = true;
    notifyListeners();
    try {
      final data = await ApiService.getInvitations();
      _incoming = data['incoming'] ?? [];
      _outgoing = data['outgoing'] ?? [];
    } catch (e) {
      debugPrint('Error fetching invites: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  // Marks every currently known incoming invite as seen, clearing the badge.
  // Called when the user opens the Invites tab.
  void markIncomingSeen() {
    for (final invite in _incoming) {
      _seenInviteIds.add(_inviteId(invite));
    }
    notifyListeners();
  }

  Future<void> respondToInvite(String inviteId, String status) async {
    await ApiService.respondToInvite(inviteId, status);
    await fetchInvites();
  }
}
