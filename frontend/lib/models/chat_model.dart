class ChatModel {
  final String chatId;
  final String contactName;
  final String? contactAvatar;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  bool isArchived;

  ChatModel({
    required this.chatId,
    required this.contactName,
    this.contactAvatar,
    this.lastMessage,
    this.lastMessageTime,
    this.isArchived = false,
  });

  factory ChatModel.fromJson(Map<String, dynamic> json) {
    return ChatModel(
      chatId: json['chat_id'] ?? '',
      contactName: json['contact_name'] ?? 'User',
      contactAvatar: json['contact_avatar'],
      lastMessage: json['last_message'],
      lastMessageTime: json['last_message_time'] != null
          ? DateTime.parse(json['last_message_time'])
          : null,
      isArchived: json['is_archived'] ?? false,
    );
  }
}