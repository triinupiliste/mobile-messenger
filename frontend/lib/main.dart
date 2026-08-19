import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/invite_provider.dart';
import 'services/notification_service.dart';
import 'services/push_notification_service.dart';
import 'services/theme_service.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'widgets/common/restart_widget.dart';

void main() {
  // App-wide crash safety net. Individual screens already handle expected
  // failures (failed API calls, etc.) with their own try/catch + SnackBars,
  // but there was previously nothing to stop a genuinely unexpected/uncaught
  // error from crashing the whole app or leaving it on a blank screen.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Errors thrown by the Flutter framework itself (e.g. during a widget's
    // build/layout/paint) are normally only printed to the console in
    // release mode while leaving the broken widget on screen. Route them
    // through the same logging path as other uncaught errors.
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
    };

    // Catches errors that reach the engine directly (e.g. from platform
    // channel callbacks) outside of the zone below.
    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('Uncaught platform error: $error\n$stack');
      return true;
    };

    // Replaces the default red "Error" screen shown when a widget throws
    // during build with a stable, branded fallback instead of a broken or
    // blank screen.
    ErrorWidget.builder = (FlutterErrorDetails details) => const _CrashFallbackScreen();

    // Apply the user's previously chosen theme (if any) before the first
    // frame, so the app doesn't flash the default theme then swap.
    await ThemeService.loadSavedTheme();

    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    // Not const: RestartWidget's builder must construct a fresh MyApp
    // instance on every theme-triggered rebuild (see restart_widget.dart) —
    // a const instance would be reused/canonicalized, making theme refreshes
    // a no-op.
    runApp(RestartWidget(builder: (context) => MyApp()));
  }, (error, stackTrace) {
    // Catches uncaught async errors (e.g. from Futures/Timers/socket
    // callbacks) that would otherwise crash the isolate.
    debugPrint('Uncaught error: $error\n$stackTrace');
  });
}

class _CrashFallbackScreen extends StatelessWidget {
  const _CrashFallbackScreen();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 12),
              Text(
                'Something went wrong',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                'Please try again.',
                style: TextStyle(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              // Gives the user an actual way forward instead of a dead end:
              // pops back to the app's root route (discarding whatever
              // broken navigation state led to the error) and forces every
              // screen to rebuild from scratch via RestartWidget, the same
              // mechanism already used to apply theme changes app-wide.
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  RestartWidget.restartApp(context);
                },
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Only 'resumed' means the app is actually visible/interactive right now.
  // paused/inactive/hidden/detached all mean the user isn't looking at it
  // (backgrounded, screen locked, in the app switcher, etc.) — even though a
  // chat screen underneath may still be fully mounted with its socket
  // listeners still registered.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    AppLifecycleTracker.setForeground(state == AppLifecycleState.resumed);
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => InviteProvider()),
      ],
      child: MaterialApp(
        navigatorKey: PushNotificationService.navigatorKey,
        title: 'Mobile Messenger',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        home: Consumer<AuthProvider>(
          builder: (context, authProvider, _) {
            if (authProvider.isLoading) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            return authProvider.isAuthenticated
                ? HomeScreen(key: HomeScreen.homeKey)
                : const LoginScreen();
          },
        ),
      ),
    );
  }
}