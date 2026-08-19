import '../theme/app_colors.dart';
import 'storage_service.dart';

/// Loads/persists the user's chosen app theme (see Settings screen).
/// AppColors.primary is the only color that changes between themes; the
/// actual switching is applied to AppColors directly.
class ThemeService {
  // Applies the previously saved theme so the app launches with the user's choice
  // instead of resetting to the default.
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
