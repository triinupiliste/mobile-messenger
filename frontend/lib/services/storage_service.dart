import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StorageService {
  static const _secureStorage = FlutterSecureStorage();
  static const String _tokenKey = 'auth_token';
  static const String _themeKey = 'app_theme';
  static const String _darkModeKey = 'app_dark_mode';

  // In-memory copy of the token, kept in sync with secure storage. Widgets
  // that build media URLs (e.g. NetworkImage) need the token synchronously,
  // which flutter_secure_storage can't provide directly since all its reads
  // are async.
  static String? _cachedToken;
  static String? get cachedToken => _cachedToken;

  static Future<void> setToken(String token) async {
    _cachedToken = token;
    await _secureStorage.write(key: _tokenKey, value: token);
  }

  static Future<String?> getToken() async {
    _cachedToken = await _secureStorage.read(key: _tokenKey);
    return _cachedToken;
  }

  static Future<void> clearToken() async {
    _cachedToken = null;
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

  // Persists the user's light/dark mode preference so it survives app
  // restarts, mirroring how the accent theme name is stored above.
  static Future<void> setDarkMode(bool isDark) async {
    await _secureStorage.write(key: _darkModeKey, value: isDark.toString());
  }

  static Future<bool> getDarkMode() async {
    final value = await _secureStorage.read(key: _darkModeKey);
    return value == 'true';
  }
}