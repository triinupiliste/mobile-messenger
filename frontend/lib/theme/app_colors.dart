import 'package:flutter/material.dart';

enum AppThemeName { sunsetCoral, calmForest, oceanBlue }

class AppColors {
  // The vibrant, "strongest" accent color — used for buttons, active icons,
  // links, and the default (no-photo) avatar background.
  static Color primary = _primaryFor(AppThemeName.sunsetCoral);

  // The lightest tint of the theme, used as the app's background.
  static Color background = _backgroundFor(AppThemeName.sunsetCoral);

  // Whether dark mode is currently active. Toggled from Settings via
  // applyDarkMode(); everything below reacts to it the same way `primary`
  // and `background` already react to the accent theme picker.
  static bool isDark = false;

  static Color secondary = _light.secondary;
  static Color surface = _light.surface;
  static const error = Color(0xFFD90429);
  static Color errorBackground = _light.errorBackground;
  static Color errorBorder = _light.errorBorder;
  static const warning = Color(0xFFFFA000);
  static const onPrimary = Colors.white;            // Text/icons drawn on colored surfaces
  static Color textPrimary = _light.textPrimary;
  static Color textSecondary = _light.textSecondary;

  // Light neutral border used on cards, bubbles, and input fields throughout
  // the app (chat bubbles, chat list rows, search field, theme swatches,
  // the global divider theme, etc.) — kept as one named constant instead of
  // the same hex literal being copy-pasted at every call site.
  static Color cardBorder = _light.cardBorder;

  // Soft drop shadow shared by low-elevation cards/bubbles (e.g. the chat
  // room's reply-preview card and the typing indicator bubble).
  static Color softShadow = _light.softShadow;

  // Slightly stronger shadow used for "floating" bottom bars (e.g. the chat
  // room's message input bar).
  static Color floatingBarShadow = _light.floatingBarShadow;

  // Darkens a color for the gradient endpoints used across primary-colored
  // buttons/badges/avatars (send button, unread badges, theme swatches,
  // "isMe" chat bubbles) so every gradient darkens by the same, named amount
  // instead of a bare `Color.lerp(color, Colors.black, 0.18)!` at each spot.
  static Color darken(Color color, [double amount = 0.18]) => Color.lerp(color, Colors.black, amount)!;

  static AppThemeName _currentTheme = AppThemeName.sunsetCoral;
  static AppThemeName get currentTheme => _currentTheme;

  static void applyTheme(AppThemeName theme) {
    _currentTheme = theme;
    primary = _primaryFor(theme);
    background = isDark ? _dark.background : _backgroundFor(theme);
  }

  // Switches every neutral (non-accent) color token between the light and
  // dark palettes. Called from Settings alongside a RestartWidget rebuild,
  // the same way applyTheme() swaps the accent color.
  static void applyDarkMode(bool dark) {
    isDark = dark;
    final palette = dark ? _dark : _light;
    background = dark ? palette.background : _backgroundFor(_currentTheme);
    secondary = palette.secondary;
    surface = palette.surface;
    textPrimary = palette.textPrimary;
    textSecondary = palette.textSecondary;
    cardBorder = palette.cardBorder;
    softShadow = palette.softShadow;
    floatingBarShadow = palette.floatingBarShadow;
    errorBackground = palette.errorBackground;
    errorBorder = palette.errorBorder;
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

// A named bundle of the neutral (non-accent) tokens that flip between light
// and dark mode, so applyDarkMode() can swap them all in one place instead
// of an easy-to-desync if/else per field.
class _NeutralPalette {
  final Color background;
  final Color secondary;
  final Color surface;
  final Color textPrimary;
  final Color textSecondary;
  final Color cardBorder;
  final Color softShadow;
  final Color floatingBarShadow;
  final Color errorBackground;
  final Color errorBorder;

  const _NeutralPalette({
    required this.background,
    required this.secondary,
    required this.surface,
    required this.textPrimary,
    required this.textSecondary,
    required this.cardBorder,
    required this.softShadow,
    required this.floatingBarShadow,
    required this.errorBackground,
    required this.errorBorder,
  });
}

const _light = _NeutralPalette(
  background: Color(0xFFFFF5F2),
  secondary: Color(0xFF2D3142), // Deep Twilight Indigo
  surface: Colors.white,
  textPrimary: Color(0xFF2D3142),
  textSecondary: Color(0xFF8D99AE),
  cardBorder: Color(0xFFEDEDF2),
  softShadow: Color(0x0D000000), // Colors.black @ 5% opacity
  floatingBarShadow: Color(0x14000000), // Colors.black @ ~8% opacity
  errorBackground: Color(0xFFFFEBEE),
  errorBorder: Color(0xFFEF9A9A),
);

const _dark = _NeutralPalette(
  background: Color(0xFF121216),
  secondary: Color(0xFFC7CBE0),
  surface: Color(0xFF1E1E24),
  textPrimary: Color(0xFFF0F0F5),
  textSecondary: Color(0xFFA0A3B8),
  cardBorder: Color(0xFF303038),
  softShadow: Color(0x33000000), // stronger shadows read against dark bg
  floatingBarShadow: Color(0x40000000),
  errorBackground: Color(0xFF3A1F22),
  errorBorder: Color(0xFF6B2E33),
);

