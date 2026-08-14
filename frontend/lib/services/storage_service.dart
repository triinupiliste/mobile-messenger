import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StorageService {
  static const _secureStorage = FlutterSecureStorage();
  static const String _tokenKey = 'auth_token';
  static const String _themeKey = 'app_theme';

  // Save the authentication token
  static Future<void> setToken(String token) async {
    await _secureStorage.write(key: _tokenKey, value: token);
  }

  // Alternative alias just in case your code calls saveToken
  static Future<void> saveToken(String token) async {
    await setToken(token);
  }

  // Retrieve the stored authentication token
  static Future<String?> getToken() async {
    return await _secureStorage.read(key: _tokenKey);
  }

  // Clear the token on logout
  static Future<void> clearToken() async {
    await _secureStorage.delete(key: _tokenKey);
  }

  // Persists the user's chosen app theme (by AppThemeName.name) so it
  // survives app restarts.
  static Future<void> setThemeName(String themeName) async {
    await _secureStorage.write(key: _themeKey, value: themeName);
  }

  static Future<String?> getThemeName() async {
    return await _secureStorage.read(key: _themeKey);
  }
}