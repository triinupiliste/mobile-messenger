import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../constants/socket_events.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/socket_service.dart';
import '../services/push_notification_service.dart';

class AuthProvider with ChangeNotifier {
  bool _isAuthenticated = false;
  bool _isLoading = true;
  bool _emailVerificationRequired = false;
  String? _forceLogoutMessage;

  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  bool get emailVerificationRequired => _emailVerificationRequired;
  // Non-null right after this device was force-logged-out because the
  // account signed in on another device — LoginScreen shows it once (as a
  // SnackBar) then clears it via clearForceLogoutMessage().
  String? get forceLogoutMessage => _forceLogoutMessage;

  void clearLoginFeedback() {
    if (!_emailVerificationRequired) return;
    _emailVerificationRequired = false;
    notifyListeners();
  }

  void clearForceLogoutMessage() {
    if (_forceLogoutMessage == null) return;
    _forceLogoutMessage = null;
    notifyListeners();
  }

  AuthProvider() {
    // Fires whenever any REST call reports SESSION_INVALIDATED (fallback for
    // when this device isn't currently socket-connected to receive the
    // real-time force_logout event below).
    ApiService.onSessionInvalidated = _handleForcedLogout;
    checkAuthStatus();
  }

  Future<void> checkAuthStatus() async {
    try {
      final token = await StorageService.getToken();
      _isAuthenticated = token != null;
      if (_isAuthenticated) {
        await SocketService.initSocket();
        await PushNotificationService.init();
        _listenForForcedLogout();
        // A stored token only proves it was valid at some point — confirm
        // with the server that it's still the active session (it may have
        // been invalidated by a login on another device while this device
        // was closed/offline) before trusting it.
        try {
          await ApiService.getProfile();
        } on SessionInvalidatedException catch (e) {
          await _handleForcedLogout(e.message);
        } catch (_) {
          // Network/server error unrelated to session validity — don't log
          // the user out just because the profile check failed to reach
          // the server; screens surface connectivity issues on their own.
        }
      }
    } catch (e) {
      _isAuthenticated = false;
    }
    _isLoading = false;
    notifyListeners();
  }

  // Listens for the server telling this device it's been signed out because
  // the account just logged in elsewhere. Safe to call repeatedly: each
  // initSocket() call creates a brand new socket instance, so this just
  // attaches the listener to whichever socket is currently active.
  void _listenForForcedLogout() {
    SocketService.on(SocketEvents.forceLogout, (data) {
      final message = (data is Map && data['message'] is String)
          ? data['message'] as String
          : 'You were logged out because your account was signed in on another device.';
      _handleForcedLogout(message);
    });
  }

  Future<void> _handleForcedLogout(String message) async {
    if (!_isAuthenticated) return;
    _isAuthenticated = false;
    _forceLogoutMessage = message;
    notifyListeners();

    try {
      await StorageService.clearToken();
    } catch (e) {
      debugPrint('Error clearing token during forced logout: $e');
    }
    try {
      SocketService.disconnect();
    } catch (e) {
      debugPrint('Error disconnecting socket during forced logout: $e');
    }
    try {
      await PushNotificationService.clearToken();
    } catch (e) {
      debugPrint('Error clearing push notification token during forced logout: $e');
    }
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
        _listenForForcedLogout();

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
