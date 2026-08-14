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
