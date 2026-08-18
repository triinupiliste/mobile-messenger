import 'package:flutter/material.dart';
import '../../services/theme_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/restart_widget.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AppThemeName _selectedTheme = AppColors.currentTheme;
  bool _isApplying = false;

  static const _themeOptions = [
    (
      theme: AppThemeName.sunsetCoral,
      label: 'Sunset Coral',
      description: 'The default warm coral theme',
    ),
    (
      theme: AppThemeName.calmForest,
      label: 'Calm Forest',
      description: 'A calm, green take on the same look',
    ),
    (
      theme: AppThemeName.oceanBlue,
      label: 'Ocean Blue',
      description: 'A fresh, modern blue palette',
    ),
  ];

  Future<void> _selectTheme(AppThemeName theme) async {
    if (theme == _selectedTheme || _isApplying) return;

    setState(() {
      _isApplying = true;
      _selectedTheme = theme;
    });

    await ThemeService.setTheme(theme);

    if (!mounted) return;
    // Restart the app UI so every screen (including ones already on the
    // navigation stack) picks up the new theme color.
    RestartWidget.restartApp(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Text(
              'App Theme',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
            ),
          ),
          for (final option in _themeOptions)
            Builder(builder: (context) {
              final swatch = AppColors.primaryFor(option.theme);
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: _selectedTheme == option.theme ? swatch : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: ListTile(
                  onTap: () => _selectTheme(option.theme),
                  leading: CircleAvatar(backgroundColor: swatch),
                  title: Text(option.label),
                  subtitle: Text(option.description),
                  trailing: _selectedTheme == option.theme
                      ? Icon(Icons.check_circle, color: swatch)
                      : const Icon(Icons.radio_button_unchecked, color: AppColors.textSecondary),
                ),
              );
            }),
        ],
      ),
    );
  }
}
