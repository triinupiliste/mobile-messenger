class NotificationSettingsService {
  static final Map<String, bool> _mutedChats = {};

  static bool isChatMuted(String chatId) {
    return _mutedChats[chatId] ?? false;
  }

  static void toggleMuteChat(String chatId) {
    _mutedChats[chatId] = !isChatMuted(chatId);
  }

  static void setChatMuted(String chatId, bool isMuted) {
    _mutedChats[chatId] = isMuted;
  }
}

// Tracks which chat (if any) is currently open on screen, so a foreground
// push notification for THAT chat can be suppressed (its messages are
// already visible live via the socket) while other chats still notify.
class ActiveChatTracker {
  static String? _activeChatId;

  static void setActiveChat(String? chatId) {
    _activeChatId = chatId;
  }

  static bool isChatActive(String chatId) {
    return _activeChatId == chatId;
  }
}

// Tracks whether the app itself is currently in the foreground (as opposed
// to backgrounded — e.g. the user switched to another app or locked the
// screen). ActiveChatTracker alone isn't enough for this: a chat screen
// stays mounted (and its socket listeners stay registered) even while the
// app is backgrounded, since the user simply switched away without
// navigating back out of it. Anything that treats "this chat is on screen"
// as "the user is actually looking at/reading it right now" — marking
// messages read, suppressing notifications — must check this too.
class AppLifecycleTracker {
  static bool _isForeground = true;

  static bool get isForeground => _isForeground;

  // Notified whenever the app transitions from backgrounded back to the
  // foreground, so anything that skipped acting while backgrounded (e.g. a
  // still-open chat screen that couldn't mark newly-arrived messages read)
  // gets a chance to catch up now that the user is actually looking again.
  static final List<void Function()> _foregroundListeners = [];

  static void addForegroundListener(void Function() listener) {
    _foregroundListeners.add(listener);
  }

  static void removeForegroundListener(void Function() listener) {
    _foregroundListeners.remove(listener);
  }

  static void setForeground(bool value) {
    final wasForeground = _isForeground;
    _isForeground = value;
    if (value && !wasForeground) {
      for (final listener in List<void Function()>.from(_foregroundListeners)) {
        listener();
      }
    }
  }
}
