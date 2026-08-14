import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../screens/chat/chat_room_screen.dart';
import '../screens/invites/invites_screen.dart';
import 'api_service.dart';
import 'notification_service.dart';

const String _pushChannelId = 'messages';
const String _pushChannelName = 'Messages & Invites';

// Must be a top-level (or static) function — FCM runs this in a separate
// background isolate when a push arrives while the app is backgrounded or
// fully terminated. The system tray already shows the notification itself
// (from the FCM `notification` payload), so there's nothing to display here;
// tap handling is done later via getInitialMessage()/onMessageOpenedApp.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class PushNotificationService {
  // Lets notification-tap handlers navigate without needing a widget-tree
  // BuildContext (the app may be launching cold when a tap is handled).
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  static Future<void> init() async {
    // One-time plugin/channel/listener setup only — must NOT gate token
    // registration below, otherwise switching accounts on the same device
    // (without a full app restart) would leave the backend's fcm_token
    // pointing at whichever user logged in first, and the new user would
    // never receive push notifications.
    if (!_initialized) {
      _initialized = true;

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();

      await _localNotifications.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload == null) return;
          _handleTap(Map<String, dynamic>.from(jsonDecode(payload)));
        },
      );

      const channel = AndroidNotificationChannel(
        _pushChannelId,
        _pushChannelName,
        description: 'New chat messages and chat invites',
        importance: Importance.high,
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      messaging.onTokenRefresh.listen((token) => ApiService.registerFcmToken(token));

      // Foreground: Android/FCM won't auto-show a system banner while the app is
      // open, so we display it ourselves — unless it's for the chat the user is
      // already looking at (its messages are already visible live on screen).
      FirebaseMessaging.onMessage.listen(_showForegroundNotification);

      // The app was backgrounded (not terminated) and the user tapped the
      // system notification to bring it back to the foreground.
      FirebaseMessaging.onMessageOpenedApp.listen((message) => _handleTap(message.data));

      // The app was fully terminated and this notification tap launched it.
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleTap(initialMessage.data);
      }
    }

    // Always (re-)register the current device's FCM token against whichever
    // user is now logged in — this must run on every login, not just the
    // first one for this app process.
    await _registerToken();
  }

  static Future<void> _registerToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await ApiService.registerFcmToken(token);
      }
    } catch (e) {
      // Non-fatal — e.g. Firebase not fully configured yet on this device.
      debugPrint('Failed to register FCM token: $e');
    }
  }

  static void _showForegroundNotification(RemoteMessage message) {
    final data = message.data;
    final chatId = data['chatId'];
    if (data['type'] == 'message' && chatId != null && ActiveChatTracker.isChatActive(chatId)) {
      // Already visible live in the open chat — no need to also notify.
      return;
    }

    final notification = message.notification;
    if (notification == null) return;

    _localNotifications.show(
      message.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _pushChannelId,
          _pushChannelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: jsonEncode(data),
    );
  }

  static void _handleTap(Map<String, dynamic> data) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    if (data['type'] == 'invite') {
      navigator.push(MaterialPageRoute(
        builder: (_) => const InvitesScreen(markSeenOnOpen: true),
      ));
    } else if (data['type'] == 'message') {
      final chatId = data['chatId'] as String?;
      if (chatId == null) return;
      navigator.push(MaterialPageRoute(
        builder: (_) => ChatRoomScreen(
          chatId: chatId,
          contactId: data['contactId'] as String? ?? '',
          contactName: data['contactName'] as String? ?? '',
        ),
      ));
    }
  }

  // Best-effort: stop this device from receiving further pushes once logged
  // out. Errors are ignored — logout must never be blocked by this.
  static Future<void> clearToken() async {
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }
}
