import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/socket_service.dart';

class AuthProvider with ChangeNotifier {
  bool _isAuthenticated = false;
  bool _isLoading = true;

  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;

  AuthProvider() {
    checkAuthStatus();
  }

  Future<void> checkAuthStatus() async {
    final token = await StorageService.getToken();
    _isAuthenticated = token != null;
    _isLoading = false;
    notifyListeners();
  }

  bool validatePasswordStrength(String password) {
    if (password.length < 8) return false;
    if (!password.contains(RegExp(r'[a-z]'))) return false;
    if (!password.contains(RegExp(r'[A-Z]'))) return false;
    if (!password.contains(RegExp(r'\d'))) return false;
    if (!password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) return false;
    return true;
  }

  Future<String?> login(String email, String password) async {
    try {
      final res = await ApiService.login(email, password);
      if (res['token'] != null) {
        _isAuthenticated = true;
        notifyListeners();
        return null;
      }
      return res['error'] ?? 'Invalid email or password.';
    } catch (e) {
      return 'Network error occurred during login.';
    }
  }

  Future<String?> register(String username, String email, String password) async {
    if (!validatePasswordStrength(password)) {
      return 'Password does not meet strength requirements.';
    }
    try {
      final res = await ApiService.register(username, email, password);
      if (res['error'] != null) {
        return res['error'];
      }
      return null;
    } catch (e) {
      return 'Network error occurred during registration.';
    }
  }

  Future<void> logout() async {
    await StorageService.clearToken();
    SocketService.disconnect();
    _isAuthenticated = false;
    notifyListeners();
  }
}