import '../theme/app_colors.dart';
import 'storage_service.dart';

/// Loads/persists the user's chosen app theme (see Settings screen).
/// AppColors.primary is the only color that changes between themes; the
/// actual switching is applied to AppColors directly.
class ThemeService {
  // Reads the previously saved theme (if any) and applies it, so the app
  // launches with the user's chosen theme instead of always resetting to
  // the default. Falls back to the default (sunset coral) if nothing was
  // saved yet, or the saved value is unrecognized.
  static Future<void> loadSavedTheme() async {
    final savedName = await StorageService.getThemeName();
    AppThemeName theme = AppThemeName.sunsetCoral;
    for (final candidate in AppThemeName.values) {
      if (candidate.name == savedName) {
        theme = candidate;
        break;
      }
    }
    final isDark = await StorageService.getDarkMode();
    AppColors.applyDarkMode(isDark);
    AppColors.applyTheme(theme);
  }

  static Future<void> setTheme(AppThemeName theme) async {
    AppColors.applyTheme(theme);
    await StorageService.setThemeName(theme.name);
  }

  static Future<void> setDarkMode(bool isDark) async {
    AppColors.applyDarkMode(isDark);
    await StorageService.setDarkMode(isDark);
  }
}
