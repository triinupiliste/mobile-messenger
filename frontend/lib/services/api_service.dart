import 'dart:convert';
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
  static Future<Map<String, dynamic>> register(String username, String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'email': email, 'password': password}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> login(String email, String password) async {
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

  // --- USER PROFILE & SEARCH ---
  static Future<Map<String, dynamic>> getProfile() async {
    final headers = await _getHeaders();
    final response = await http.get(Uri.parse('$baseUrl/users/profile'), headers: headers);
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to fetch profile');
  }

  static Future<List<dynamic>> searchUsers(String query) async {
    final headers = await _getHeaders();
    final response = await http.get(Uri.parse('$baseUrl/users/search?query=$query'), headers: headers);
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return [];
  }

  // --- CHATS & INVITATIONS ---
  static Future<List<dynamic>> getChats() async {
    final headers = await _getHeaders();
    final response = await http.get(Uri.parse('$baseUrl/chats'), headers: headers);
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return [];
  }
}