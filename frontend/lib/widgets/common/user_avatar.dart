import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Displays a user's uploaded profile picture, or a deterministic
/// initials-based default avatar (similar to WhatsApp/Slack) when no
/// picture has been set yet, instead of a generic placeholder icon.
class UserAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String displayName;
  final double radius;

  const UserAvatar({
    super.key,
    required this.avatarUrl,
    required this.displayName,
    this.radius = 24,
  });

  static const List<Color> _palette = [
    Color(0xFFEF5350),
    Color(0xFFAB47BC),
    Color(0xFF5C6BC0),
    Color(0xFF29B6F6),
    Color(0xFF26A69A),
    Color(0xFF9CCC65),
    Color(0xFFFFA726),
    Color(0xFF8D6E63),
  ];

  Color _colorForName(String name) {
    if (name.isEmpty) return AppColors.primary;
    final hash = name.codeUnits.fold<int>(0, (sum, c) => sum + c);
    return _palette[hash % _palette.length];
  }

  String get _initial {
    final trimmed = displayName.trim();
    return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final hasUrl = avatarUrl != null && avatarUrl!.isNotEmpty;

    return CircleAvatar(
      radius: radius,
      backgroundColor: hasUrl ? AppColors.primary.withOpacity(0.1) : _colorForName(displayName),
      backgroundImage: hasUrl ? NetworkImage(avatarUrl!) : null,
      child: hasUrl
          ? null
          : Text(
              _initial,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: radius * 0.7,
              ),
            ),
    );
  }
}
