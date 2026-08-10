class MessageModel {
  final String messageId;
  final String chatId;
  final String senderId;
  final String content;
  final String? mediaUrl;
  final String mediaType;
  final String status; // 'sent', 'delivered', 'read'
  final bool isEdited;
  final DateTime createdAt;

  MessageModel({
    required this.messageId,
    required this.chatId,
    required this.senderId,
    required this.content,
    this.mediaUrl,
    required this.mediaType,
    required this.status,
    required this.isEdited,
    required this.createdAt,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      messageId: json['message_id'] ?? '',
      chatId: json['chat_id'] ?? '',
      senderId: json['sender_id'] ?? '',
      content: json['content'] ?? '',
      mediaUrl: json['media_url'],
      mediaType: json['media_type'] ?? 'text',
      status: json['status'] ?? 'sent',
      isEdited: json['is_edited'] ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }
}