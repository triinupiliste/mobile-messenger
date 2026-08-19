import 'package:flutter/material.dart';
import '../constants/socket_events.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../utils/json_utils.dart';

class InviteProvider with ChangeNotifier {
  List<dynamic> _incoming = [];
  List<dynamic> _outgoing = [];
  bool _isLoading = false;
  bool _socketListenerAttached = false;

  // Incoming invite ids the user has already looked at (i.e. had the Invites
  // tab open since they arrived). Drives the badge on the bottom nav icon.
  final Set<String> _seenInviteIds = {};

  // Stored so dispose() can unregister exactly these callbacks.
  late final void Function(dynamic) _onNewInvite;
  late final void Function(dynamic) _onInviteResponded;
  late final void Function(dynamic) _onProfileUpdated;

  List<dynamic> get incoming => _incoming;
  List<dynamic> get outgoing => _outgoing;
  bool get isLoading => _isLoading;

  int get unseenCount =>
      _incoming.where((invite) => !_seenInviteIds.contains(_inviteId(invite))).length;

  String _inviteId(dynamic invite) => (invite['id'] ?? invite['_id'] ?? '').toString();

  Future<void> fetchInvites() async {
    _isLoading = true;
    notifyListeners();

    // Retry attaching in case the socket wasn't ready yet at app startup.
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
      _onNewInvite = (data) {
        final id = _inviteId(data);
        if (id.isEmpty || _incoming.any((invite) => _inviteId(invite) == id)) return;
        _incoming = [data, ..._incoming];
        notifyListeners();
      };
      SocketService.on(SocketEvents.newInvite, _onNewInvite);

      _onInviteResponded = (data) {
        final id = _inviteId(data);
        final index = _outgoing.indexWhere((invite) => _inviteId(invite) == id);
        if (index == -1) return;
        // Responded invites (accepted/declined) no longer show up in the
        // pending outgoing list, matching what a fresh fetch would return.
        _outgoing = List.of(_outgoing)..removeAt(index);
        notifyListeners();
      };
      SocketService.on(SocketEvents.inviteResponded, _onInviteResponded);

      // A sender/recipient we have a pending invite with changed their username/avatar.
      _onProfileUpdated = (data) {
        final userId = extractUserId(data, 'userId');
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
      };
      SocketService.on(SocketEvents.profileUpdated, _onProfileUpdated);

      _socketListenerAttached = true;
    } catch (e) {
      debugPrint('Socket listener initialization deferred: $e');
    }
  }

  Future<void> respondToInvite(String inviteId, String status) async {
    await ApiService.respondToInvite(inviteId, status);
    // Remove it immediately rather than waiting on the refresh below, so it can't be
    // responded to twice if that call is slow or fails.
    _incoming = _incoming.where((invite) => _inviteId(invite) != inviteId).toList();
    notifyListeners();
    await fetchInvites();
  }

  @override
  void dispose() {
    if (_socketListenerAttached) {
      SocketService.off(SocketEvents.newInvite, _onNewInvite);
      SocketService.off(SocketEvents.inviteResponded, _onInviteResponded);
      SocketService.off(SocketEvents.profileUpdated, _onProfileUpdated);
    }
    super.dispose();
  }
}
