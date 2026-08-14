import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Displays a user's uploaded profile picture, or a default initials avatar
/// (similar to WhatsApp/Slack) when no picture has been set yet, instead of a
/// generic placeholder icon. The default avatar always uses the app's
/// current theme's strongest (primary) color, so it stays consistent with
/// the rest of the UI and updates automatically when the theme changes.
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

  String get _initial {
    final trimmed = displayName.trim();
    return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final hasUrl = avatarUrl != null && avatarUrl!.isNotEmpty;

    return CircleAvatar(
      radius: radius,
      backgroundColor: hasUrl ? AppColors.primary.withOpacity(0.1) : AppColors.primary,
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

