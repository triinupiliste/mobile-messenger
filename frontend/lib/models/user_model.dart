class UserModel {
  final String id;
  final String username;
  final String email;
  final String? avatarUrl;
  final String? aboutMe;
  final String relationshipStatus; // 'friends', 'pending', or 'none'
  final String? chatId; // Present when relationshipStatus == 'friends'

  UserModel({
    required this.id,
    required this.username,
    required this.email,
    this.avatarUrl,
    this.aboutMe,
    this.relationshipStatus = 'none',
    this.chatId,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: (json['user_id'] ?? json['id'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      avatarUrl: _optionalString(json['avatar_url']),
      aboutMe: _optionalString(json['about_me']),
      relationshipStatus: (json['relationship_status'] ?? 'none').toString(),
      chatId: _optionalString(json['chat_id']),
    );
  }

  static String? _optionalString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}