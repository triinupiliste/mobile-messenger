class InviteModel {
  final String inviteId;
  final String senderId;
  final String senderUsername;
  final String? senderAvatar;
  final DateTime createdAt;

  InviteModel({
    required this.inviteId,
    required this.senderId,
    required this.senderUsername,
    this.senderAvatar,
    required this.createdAt,
  });

  factory InviteModel.fromJson(Map<String, dynamic> json) {
    return InviteModel(
      inviteId: json['invite_id'] ?? '',
      senderId: json['sender_id'] ?? '',
      senderUsername: json['sender_username'] ?? 'User',
      senderAvatar: json['sender_avatar'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }
}