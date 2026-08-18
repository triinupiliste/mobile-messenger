import 'package:flutter/material.dart';

enum AppThemeName { sunsetCoral, calmForest, oceanBlue }

class AppColors {
  // The vibrant, "strongest" accent color — used for buttons, active icons,
  // links, and the default (no-photo) avatar background.
  static Color primary = _primaryFor(AppThemeName.sunsetCoral);

  // The lightest tint of the theme, used as the app's background.
  static Color background = _backgroundFor(AppThemeName.sunsetCoral);

  static const secondary = Color(0xFF2D3142);   // Deep Twilight Indigo
  static const surface = Colors.white;
  static const error = Color(0xFFD90429);
  static const errorBackground = Color(0xFFFFEBEE); // Light red backdrop for error banners
  static const errorBorder = Color(0xFFEF9A9A);     // Border tone paired with errorBackground
  static const warning = Color(0xFFFFA000);         // Amber accent for archive-style actions
  static const onPrimary = Colors.white;            // Text/icons drawn on colored surfaces
  static const textPrimary = Color(0xFF2D3142);
  static const textSecondary = Color(0xFF8D99AE);

  static AppThemeName _currentTheme = AppThemeName.sunsetCoral;
  static AppThemeName get currentTheme => _currentTheme;

  static void applyTheme(AppThemeName theme) {
    _currentTheme = theme;
    primary = _primaryFor(theme);
    background = _backgroundFor(theme);
  }

  // Public accessor so UI that needs to show a specific theme's swatch
  // (e.g. the theme picker in Settings) can reference the same values as
  // applyTheme() instead of duplicating the hex literals.
  static Color primaryFor(AppThemeName theme) => _primaryFor(theme);

  static Color _primaryFor(AppThemeName theme) {
    switch (theme) {
      case AppThemeName.calmForest:
        return const Color(0xFF3F9142); // Vibrant Calm Forest Green
      case AppThemeName.sunsetCoral:
        return const Color(0xFFFF6B6B); // Vibrant Sunset Coral
      case AppThemeName.oceanBlue:
        return const Color(0xFF1E88E5); // Ocean Blue Primary
    }
  }

  static Color _backgroundFor(AppThemeName theme) {
    switch (theme) {
      case AppThemeName.calmForest:
        return const Color(0xFFF1F8F2); // Lightest Calm Forest Green
      case AppThemeName.sunsetCoral:
        return const Color(0xFFFFF5F2); // Soft Warm Sand / Peach
      case AppThemeName.oceanBlue:
        return const Color(0xFFE3F2FD); // Ocean Blue Background Tint
    }
  }
}
