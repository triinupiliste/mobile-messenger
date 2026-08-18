import 'package:flutter/material.dart';
import '../constants/socket_events.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

class InviteProvider with ChangeNotifier {
  List<dynamic> _incoming = [];
  List<dynamic> _outgoing = [];
  bool _isLoading = false;
  bool _socketListenerAttached = false;

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

    // Retry attaching the socket listener here too, in case the socket wasn't
    // ready yet the first time (e.g. right at app startup before login
    // finishes connecting it).
    _initGlobalSocketListener();

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

  // Listen globally so the Invites screen (and the nav badge) update the
  // instant a new invite arrives or one of ours gets responded to, instead of
  // only refreshing the next time the screen is opened.
  void _initGlobalSocketListener() {
    if (_socketListenerAttached) return;
    try {
      SocketService.socket.on(SocketEvents.newInvite, (data) {
        final id = _inviteId(data);
        if (id.isEmpty || _incoming.any((invite) => _inviteId(invite) == id)) return;
        _incoming = [data, ..._incoming];
        notifyListeners();
      });

      SocketService.socket.on(SocketEvents.inviteResponded, (data) {
        final id = _inviteId(data);
        final index = _outgoing.indexWhere((invite) => _inviteId(invite) == id);
        if (index == -1) return;
        // Responded invites (accepted/declined) no longer show up in the
        // pending outgoing list, matching what a fresh fetch would return.
        _outgoing = List.of(_outgoing)..removeAt(index);
        notifyListeners();
      });

      // A sender/recipient we have a pending invite with changed their
      // username/avatar — patch it into the incoming/outgoing lists so it
      // updates live instead of only after the next fetchInvites().
      SocketService.socket.on(SocketEvents.profileUpdated, (data) {
        final userId = data['userId']?.toString() ?? data['user_id']?.toString();
        if (userId == null) return;
        var changed = false;

        _incoming = _incoming.map((invite) {
          final sender = invite['sender'];
          if (sender is Map && sender['id']?.toString() == userId) {
            changed = true;
            final updatedSender = Map<String, dynamic>.from(sender);
            if (data['username'] != null) updatedSender['username'] = data['username'];
            if (data['avatar_url'] != null) updatedSender['avatar_url'] = data['avatar_url'];
            return {...Map<String, dynamic>.from(invite), 'sender': updatedSender};
          }
          return invite;
        }).toList();

        _outgoing = _outgoing.map((invite) {
          final recipient = invite['recipient'];
          if (recipient is Map && recipient['id']?.toString() == userId) {
            changed = true;
            final updatedRecipient = Map<String, dynamic>.from(recipient);
            if (data['username'] != null) updatedRecipient['username'] = data['username'];
            if (data['avatar_url'] != null) updatedRecipient['avatar_url'] = data['avatar_url'];
            return {...Map<String, dynamic>.from(invite), 'recipient': updatedRecipient};
          }
          return invite;
        }).toList();

        if (changed) notifyListeners();
      });

      _socketListenerAttached = true;
    } catch (e) {
      debugPrint('Socket listener initialization deferred: $e');
    }
  }

  Future<void> respondToInvite(String inviteId, String status) async {
    await ApiService.respondToInvite(inviteId, status);
    // Remove it immediately rather than waiting on the fetchInvites() refresh
    // below — if that refresh call is slow or fails (network hiccup), the
    // invite would otherwise keep showing with working Accept/Decline
    // buttons, letting it be responded to again even though the backend
    // already processed it.
    _incoming = _incoming.where((invite) => _inviteId(invite) != inviteId).toList();
    notifyListeners();
    await fetchInvites();
  }
}
