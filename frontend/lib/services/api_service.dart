import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'storage_service.dart';

class ApiService {
  // Use 10.0.2.2 for Android Emulator, localhost for iOS simulator or Web
  static const String baseUrl = 'http://127.0.0.1:5000/api';

  static Future<Map<String, String>> _getHeaders() async {
    final token = await StorageService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // --- AUTHENTICATION ---
  static Future<Map<String, dynamic>> register(
      String username, String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(
          {'username': username, 'email': email, 'password': password}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> login(
      String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && data['token'] != null) {
      await StorageService.saveToken(data['token']);
    }
    return data;
  }

  static Future<Map<String, dynamic>> resendVerificationEmail(
      String email) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/resend-verification'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email.trim()}),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(data['error'] ?? 'Failed to send verification email');
    }
    return data;
  }

  static Future<Map<String, dynamic>> requestPasswordReset(String email) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/request-password-reset'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email.trim()}),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(data['error'] ?? 'Failed to request password reset');
    }
    return data;
  }

  // --- USER PROFILE & SEARCH ---
  static Future<Map<String, dynamic>> getProfile() async {
    final headers = await _getHeaders();
    final response =
        await http.get(Uri.parse('$baseUrl/users/profile'), headers: headers);
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to fetch profile');
  }

  static Future<Map<String, dynamic>> updateProfile({
    String? avatarUrl,
    String? aboutMe,
  }) async {
    final headers = await _getHeaders();
    final response = await http.put(
      Uri.parse('$baseUrl/users/profile'),
      headers: headers,
      body: jsonEncode({
        'avatar_url': avatarUrl,
        'about_me': aboutMe,
      }),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(data['profile']);
    }
    throw Exception(data['error'] ?? 'Failed to update profile');
  }

  static Future<List<dynamic>> searchUsers(String query) async {
    if (query.trim().isEmpty) return [];

    final token = await StorageService.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('Your session has expired. Please log in again.');
    }

    final response = await http.get(
      Uri.parse('$baseUrl/users/search?q=${Uri.encodeComponent(query.trim())}'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    ).timeout(
      const Duration(seconds: 8),
      onTimeout: () => throw Exception(
        'The server could not be reached. Check the backend connection.',
      ),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is List) return data;
      if (data is Map && data['users'] is List) return data['users'];
      return [];
    } else if (response.statusCode == 400) {
      return [];
    } else {
      final data = jsonDecode(response.body);
      throw Exception(data['error'] ?? 'Failed to search users');
    }
  }

  static Future<void> sendInvite(String recipientId) async {
    final token = await StorageService.getToken();
    final response = await http.post(
      Uri.parse('$baseUrl/invites'), // Matches backend router.post('/')
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'receiverId': recipientId
      }), // Matches req.body.receiverId in controller
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      final data = jsonDecode(response.body);
      throw Exception(data['error'] ?? 'Failed to send invite');
    }
  }

  static Future<Map<String, dynamic>> getInvitations() async {
    final token = await StorageService.getToken();
    final response = await http.get(
      Uri.parse('$baseUrl/invites'), // Matches backend router.get('/')
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic>) {
        return {
          'incoming': data['incoming'] ?? [],
          'outgoing': data['outgoing'] ?? [],
        };
      }
    }

    final data = jsonDecode(response.body);
    throw Exception(data['error'] ?? 'Failed to load invitations');
  }

  static Future<void> respondToInvite(String inviteId, String status) async {
    final token = await StorageService.getToken();
    final response = await http.post(
      Uri.parse('$baseUrl/invites/respond'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(
          {'inviteId': inviteId, 'status': status}), // 'accepted' or 'declined'
    );

    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['error'] ?? 'Failed to respond to invite');
    }
  }

  // --- CHATS & INVITATIONS ---
  static Future<List<dynamic>> getChats() async {
    final headers = await _getHeaders();
    final response =
        await http.get(Uri.parse('$baseUrl/chats'), headers: headers);
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return [];
  }

  static Future<List<dynamic>> getMessages(String chatId) async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/chats/$chatId/messages'),
      headers: headers,
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is List) return data;
    }
    return [];
  }

  static Future<void> markChatMessagesRead(String chatId) async {
    final headers = await _getHeaders();
    await http.patch(
      Uri.parse('$baseUrl/chats/$chatId/read'),
      headers: headers,
    );
  }

  // Uploads a local media file (image, video, or voice note) and returns its
  // publicly reachable URL so it can be sent as a message's mediaUrl.
  static Future<String> uploadMedia(File file) async {
    final token = await StorageService.getToken();
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/media/upload'),
    );
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    request.files.add(await http.MultipartFile.fromPath('file', file.path));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['url'] as String;
    }

    final data = jsonDecode(response.body);
    throw Exception(data['error'] ?? 'Failed to upload media.');
  }
}
