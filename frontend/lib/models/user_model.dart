class UserModel {
  final String id;
  final String username;
  final String email;
  final String? avatarUrl;
  final String? aboutMe;

  UserModel({
    required this.id,
    required this.username,
    required this.email,
    this.avatarUrl,
    this.aboutMe,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['user_id'] ?? json['id'] ?? '',
      username: json['username'] ?? '',
      email: json['email'] ?? '',
      avatarUrl: json['avatar_url'],
      aboutMe: json['about_me'],
    );
  }
}