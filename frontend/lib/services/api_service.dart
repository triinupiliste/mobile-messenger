import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../config/server_config.dart';
import 'storage_service.dart';

// The http package's MultipartFile.fromPath() does NOT infer a content-type
// from the file's extension — it silently defaults to
// application/octet-stream unless one is passed explicitly. The backend's
// avatar upload endpoint filters on the multipart file's mimetype, so without
// this every avatar upload (including PNGs) was being rejected regardless of
// the actual image format.
MediaType? _imageContentTypeForPath(String path) {
  final extension = path.split('.').last.toLowerCase();
  switch (extension) {
    case 'jpg':
    case 'jpeg':
      return MediaType('image', 'jpeg');
    case 'png':
      return MediaType('image', 'png');
    default:
      return null;
  }
}

class ApiService {
  static const String baseUrl = '$serverBaseUrl/api';

  static const Map<String, String> ngrokHeader = {
    'ngrok-skip-browser-warning': 'true',
  };

  // ngrok's free tier serves an HTML interstitial warning page to any
  // non-browser request unless this header is present, which would
  // otherwise break JSON parsing for every API call. Exposed publicly so
  // other services making their own native network requests for media URLs
  // (video thumbnail generation, video playback) can send it too.
  static const Map<String, String> _ngrokHeader = ngrokHeader;

  static Future<Map<String, String>> _getHeaders() async {
    final token = await StorageService.getToken();
    return {
      'Content-Type': 'application/json',
      ..._ngrokHeader,
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // The /uploads/:filename endpoint requires a JWT, but native media widgets
  // (Image.network, NetworkImage, VideoPlayerController, video_thumbnail,
  // audioplayers) fetch a URL directly and can't attach an Authorization
  // header, so the token is appended as a query parameter instead. Call this
  // wherever a media URL from the backend is handed to one of those APIs.
  //
  // The backend now returns/stores these as paths relative to itself (e.g.
  // '/uploads/xyz.jpg') rather than a full URL, since the host (e.g. an
  // ngrok tunnel) can change between restarts — a baked-in absolute URL
  // would otherwise turn into a dead link the next time that happens. Old
  // rows created before this change may still hold a full absolute URL;
  // those are left as-is here (already a dead link if the host has since
  // changed — re-saving/re-uploading fixes it).
  static String mediaUrl(String url) {
    final absoluteUrl = url.startsWith('http://') || url.startsWith('https://')
        ? url
        : '$serverBaseUrl$url';
    final token = StorageService.cachedToken;
    if (token == null || token.isEmpty) return absoluteUrl;
    final uri = Uri.tryParse(absoluteUrl);
    if (uri == null) return absoluteUrl;
    final query = Map<String, String>.from(uri.queryParameters)..['token'] = token;
    return uri.replace(queryParameters: query).toString();
  }

  // --- AUTHENTICATION ---
  static Future<Map<String, dynamic>> register(
      String username, String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json', ..._ngrokHeader},
      body: jsonEncode(
          {'username': username, 'email': email, 'password': password}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> login(
      String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json', ..._ngrokHeader},
      body: jsonEncode({'email': email, 'password': password}),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && data['token'] != null) {
      await StorageService.setToken(data['token']);
    }
    return data;
  }

  static Future<Map<String, dynamic>> resendVerificationEmail(
      String email) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/resend-verification'),
      headers: {'Content-Type': 'application/json', ..._ngrokHeader},
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
      headers: {'Content-Type': 'application/json', ..._ngrokHeader},
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

  // Fetches another user's public profile (username, email, avatar, about me).
  static Future<Map<String, dynamic>> getUserProfile(String userId) async {
    final headers = await _getHeaders();
    final response =
        await http.get(Uri.parse('$baseUrl/users/$userId'), headers: headers);
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(data);
    }
    throw Exception(data['error'] ?? 'Failed to fetch user profile');
  }

  static Future<Map<String, dynamic>> updateProfile({
    String? username,
    String? email,
    String? avatarUrl,
    String? aboutMe,
  }) async {
    final headers = await _getHeaders();
    final response = await http.put(
      Uri.parse('$baseUrl/users/profile'),
      headers: headers,
      body: jsonEncode({
        if (username != null) 'username': username,
        if (email != null) 'email': email,
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
        ..._ngrokHeader,
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
        ..._ngrokHeader,
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
        ..._ngrokHeader,
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
        ..._ngrokHeader,
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

  static Future<void> setChatMuted(String chatId, bool isMuted) async {
    final headers = await _getHeaders();
    await http.patch(
      Uri.parse('$baseUrl/chats/$chatId/mute'),
      headers: headers,
      body: jsonEncode({'isMuted': isMuted}),
    );
  }

  static Future<void> setChatArchived(String chatId, bool isArchived) async {
    final headers = await _getHeaders();
    await http.patch(
      Uri.parse('$baseUrl/chats/$chatId/archive'),
      headers: headers,
      body: jsonEncode({'isArchived': isArchived}),
    );
  }

  static Future<void> setChatDeleted(String chatId, bool isDeleted) async {
    final headers = await _getHeaders();
    await http.patch(
      Uri.parse('$baseUrl/chats/$chatId/delete'),
      headers: headers,
      body: jsonEncode({'isDeleted': isDeleted}),
    );
  }

  static Future<void> removeFriend(String chatId) async {
    final headers = await _getHeaders();
    await http.patch(
      Uri.parse('$baseUrl/chats/$chatId/remove-friend'),
      headers: headers,
    );
  }

  // --- PUSH NOTIFICATIONS ---
  static Future<void> registerFcmToken(String fcmToken) async {
    final headers = await _getHeaders();
    await http.put(
      Uri.parse('$baseUrl/users/fcm-token'),
      headers: headers,
      body: jsonEncode({'fcmToken': fcmToken}),
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
    request.headers.addAll(_ngrokHeader);
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

  // Uploads a profile picture. Unlike uploadMedia, the backend restricts this
  // endpoint to JPEG/PNG and a 5MB limit.
  static Future<String> uploadAvatar(File file) async {
    final token = await StorageService.getToken();
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/media/avatar'),
    );
    request.headers.addAll(_ngrokHeader);
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    request.files.add(await http.MultipartFile.fromPath(
      'file',
      file.path,
      contentType: _imageContentTypeForPath(file.path),
    ));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['url'] as String;
    }

    final data = jsonDecode(response.body);
    throw Exception(data['error'] ?? 'Failed to upload profile picture.');
  }
}
