import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../../services/api_service.dart';
import '../../theme/app_colors.dart';

/// Displays a user's uploaded profile picture, or a default initials avatar
/// when none has been set. The default avatar uses the app's current theme
/// color and updates automatically when the theme changes.
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
    final size = radius * 2;

    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.darken(AppColors.primary)],
        ),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: ClipOval(
        child: hasUrl
            ? CachedNetworkImage(
                imageUrl: ApiService.mediaUrl(avatarUrl!),
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 200),
                placeholder: (context, url) => Shimmer.fromColors(
                  baseColor: AppColors.cardBorder,
                  highlightColor: AppColors.background,
                  child: Container(color: Colors.white),
                ),
                errorWidget: (context, url, error) => Container(
                  color: AppColors.primary,
                  alignment: Alignment.center,
                  child: Text(
                    _initial,
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: radius * 0.7),
                  ),
                ),
              )
            : Container(
                color: AppColors.surface,
                alignment: Alignment.center,
                child: Text(
                  _initial,
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: radius * 0.7,
                  ),
                ),
              ),
      ),
    );
  }
}


