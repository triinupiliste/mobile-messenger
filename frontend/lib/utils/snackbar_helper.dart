import 'package:flutter/material.dart';

/// Centralizes SnackBar presentation so every screen gets the same default
/// duration/dismiss behavior instead of hand-rolling `SnackBar(...)` everywhere.
class SnackBarHelper {
  SnackBarHelper._();

  static const Duration defaultDuration = Duration(seconds: 4);

  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> show(
    BuildContext context,
    String message, {
    Duration duration = defaultDuration,
    SnackBarAction? action,
  }) {
    return ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: duration, action: action),
    );
  }

  // For call sites that must capture the ScaffoldMessengerState before an
  // async gap or a Navigator.pop (e.g. once a route is gone, `context` can no
  // longer be used to look one up).
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showWithMessenger(
    ScaffoldMessengerState messenger,
    String message, {
    Duration duration = defaultDuration,
    SnackBarAction? action,
  }) {
    return messenger.showSnackBar(
      SnackBar(content: Text(message), duration: duration, action: action),
    );
  }
}
