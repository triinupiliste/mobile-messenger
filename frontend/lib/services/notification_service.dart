class NotificationSettingsService {
  static final Map<String, bool> _mutedChats = {};

  static bool isChatMuted(String chatId) {
    return _mutedChats[chatId] ?? false;
  }

  static void toggleMuteChat(String chatId) {
    _mutedChats[chatId] = !isChatMuted(chatId);
  }
}