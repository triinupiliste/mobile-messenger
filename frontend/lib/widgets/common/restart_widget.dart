import 'package:flutter/material.dart';

/// Wraps the app so it can be told to rebuild itself from the top down —
/// used after changing the app theme so every currently-built screen,
/// including ones already pushed onto the navigation stack, picks up the new
/// colors. Takes a builder (rather than a plain child widget) specifically
/// so each rebuild constructs a genuinely new widget instance: Flutter skips
/// rebuilding a subtree entirely if the exact same widget instance is
/// returned again (its "identical widget" fast path), which would make
/// restartApp() a no-op if we just stored and returned a single fixed
/// `child` widget. This also deliberately avoids changing any Keys (unlike a
/// hard reset that recreates the subtree from scratch with a brand new key)
/// so the Navigator's state is preserved — the user stays on whatever
/// screen they're on (e.g. Settings) instead of being bounced back to the
/// home screen and losing the route.
class RestartWidget extends StatefulWidget {
  final WidgetBuilder builder;

  const RestartWidget({super.key, required this.builder});

  static void restartApp(BuildContext context) {
    context.findAncestorStateOfType<_RestartWidgetState>()?.restartApp();
  }

  @override
  State<RestartWidget> createState() => _RestartWidgetState();
}

class _RestartWidgetState extends State<RestartWidget> {
  void restartApp() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context);
  }
}
