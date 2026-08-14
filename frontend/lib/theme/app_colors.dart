import 'package:flutter/material.dart';

enum AppThemeName { sunsetCoral, calmForest }

class AppColors {
  // The vibrant, "strongest" accent color — used for buttons, active icons,
  // links, and the default (no-photo) avatar background.
  static Color primary = _primaryFor(AppThemeName.sunsetCoral);

  // The lightest tint of the theme, used as the app's background.
  static Color background = _backgroundFor(AppThemeName.sunsetCoral);

  static const secondary = Color(0xFF2D3142);   // Deep Twilight Indigo
  static const surface = Colors.white;
  static const error = Color(0xFFD90429);
  static const textPrimary = Color(0xFF2D3142);
  static const textSecondary = Color(0xFF8D99AE);

  static AppThemeName _currentTheme = AppThemeName.sunsetCoral;
  static AppThemeName get currentTheme => _currentTheme;

  static void applyTheme(AppThemeName theme) {
    _currentTheme = theme;
    primary = _primaryFor(theme);
    background = _backgroundFor(theme);
  }

  static Color _primaryFor(AppThemeName theme) {
    switch (theme) {
      case AppThemeName.calmForest:
        return const Color(0xFF3F9142); // Vibrant Calm Forest Green
      case AppThemeName.sunsetCoral:
        return const Color(0xFFFF6B6B); // Vibrant Sunset Coral
    }
  }

  static Color _backgroundFor(AppThemeName theme) {
    switch (theme) {
      case AppThemeName.calmForest:
        return const Color(0xFFF1F8F2); // Lightest Calm Forest Green
      case AppThemeName.sunsetCoral:
        return const Color(0xFFFFF5F2); // Soft Warm Sand / Peach
    }
  }
}
