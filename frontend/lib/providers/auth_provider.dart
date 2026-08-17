import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/socket_service.dart';
import '../services/push_notification_service.dart';

class AuthProvider with ChangeNotifier {
  bool _isAuthenticated = false;
  bool _isLoading = true;
  bool _emailVerificationRequired = false;

  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  bool get emailVerificationRequired => _emailVerificationRequired;

  void clearLoginFeedback() {
    if (!_emailVerificationRequired) return;
    _emailVerificationRequired = false;
    notifyListeners();
  }

  AuthProvider() {
    checkAuthStatus();
  }

  Future<void> checkAuthStatus() async {
    try {
      final token = await StorageService.getToken();
      _isAuthenticated = token != null;
      if (_isAuthenticated) {
        await SocketService.initSocket();
        await PushNotificationService.init();
      }
    } catch (e) {
      _isAuthenticated = false;
    }
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
        // CRITICAL: Save the token securely so it persists across app restarts!
        await StorageService.setToken(res['token']);
        await SocketService.initSocket();
        await PushNotificationService.init();

        _isAuthenticated = true;
        _emailVerificationRequired = false;
        notifyListeners();
        return null;
      }
      _emailVerificationRequired = res['code'] == 'EMAIL_NOT_VERIFIED';
      notifyListeners();
      return res['error'] ?? 'Invalid email or password.';
    } catch (e) {
      return 'Network error occurred during login.';
    }
  }

  Future<String?> resendVerificationEmail(String email) async {
    try {
      final response = await ApiService.resendVerificationEmail(email);
      return response['message'] as String?;
    } catch (error) {
      return error.toString().replaceFirst('Exception: ', '');
    }
  }

  Future<String?> requestPasswordReset(String email) async {
    try {
      final response = await ApiService.requestPasswordReset(email);
      return response['message'] as String?;
    } catch (error) {
      return error.toString().replaceFirst('Exception: ', '');
    }
  }

  Future<String?> register(
      String username, String email, String password) async {
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
      debugPrint(
          'Registration Exception: $e'); // <-- This prints the exact cause in your terminal
      return 'Network error occurred during registration: $e';
    }
  }

  Future<void> logout() async {
    // Switch to the login screen immediately. Cleanup must not block logout.
    _isAuthenticated = false;
    _emailVerificationRequired = false;
    notifyListeners();

    try {
      await StorageService.clearToken();
    } catch (e) {
      debugPrint('Error clearing token: $e');
    }

    try {
      SocketService.disconnect();
    } catch (e) {
      debugPrint('Error disconnecting socket: $e');
    }

    try {
      await PushNotificationService.clearToken();
    } catch (e) {
      debugPrint('Error clearing push notification token: $e');
    }
  }
}
