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
    // Rebuild the app UI so every screen (including ones already on the
    // navigation stack) picks up the new theme color, without disrupting
    // navigation or this screen's own state.
    RestartWidget.restartApp(context);
    setState(() => _isApplying = false);
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
              final selected = _selectedTheme == option.theme;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: selected ? swatch : const Color(0xFFEDEDF2), width: selected ? 2 : 1),
                  boxShadow: [
                    BoxShadow(
                      color: (selected ? swatch : Colors.black).withValues(alpha: selected ? 0.18 : 0.04),
                      blurRadius: selected ? 14 : 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => _selectTheme(option.theme),
                    child: ListTile(
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [swatch, Color.lerp(swatch, Colors.black, 0.18)!],
                          ),
                          boxShadow: [
                            BoxShadow(color: swatch.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 2)),
                          ],
                        ),
                      ),
                      title: Text(option.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(option.description),
                      trailing: selected
                          ? Icon(Icons.check_circle, color: swatch)
                          : const Icon(Icons.radio_button_unchecked, color: AppColors.textSecondary),
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
