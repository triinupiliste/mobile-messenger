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

int _notificationIdForChat(String chatId) => chatId.hashCode;

const AndroidNotificationChannel _pushChannel = AndroidNotificationChannel(
  _pushChannelId,
  _pushChannelName,
  description: 'New chat messages and chat invites',
  importance: Importance.high,
);

// Shared by both the foreground listener and the background isolate handler
// below, so a chat's notification always gets the same stable id (letting it
// be replaced/cancelled later) regardless of which path displayed it. The
// backend sends data-only messages (no top-level `notification` block) so
// the OS never auto-displays these itself — this is the only place that does.
Future<void> _displayMessageNotification(
  FlutterLocalNotificationsPlugin plugin,
  Map<String, dynamic> data,
) async {
  final chatId = data['chatId'] as String?;
  if (data['type'] == 'message' && chatId != null && ActiveChatTracker.isChatActive(chatId)) {
    // Already visible live in the open chat — no need to also notify.
    return;
  }

  final title = data['title'] as String?;
  final body = data['body'] as String?;
  if (title == null || body == null) return;

  // Use a stable per-chat id (rather than a per-message hash) so a newer
  // message for the same chat replaces the previous tray notification
  // instead of stacking, and so it can be cancelled later by chat id (e.g.
  // once the user reads it, whether via the app or the notification).
  final notificationId =
      data['type'] == 'message' && chatId != null ? _notificationIdForChat(chatId) : data.hashCode;

  await plugin.show(
    notificationId,
    title,
    body,
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

// Must be a top-level (or static) function — FCM runs this in a separate
// background isolate when a push arrives while the app is backgrounded or
// fully terminated. Since the backend now sends data-only messages, nothing
// gets shown automatically — this has to display it itself, using its own
// plugin instance since it doesn't share memory with the main isolate that
// PushNotificationService normally runs in.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
  await plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_pushChannel);

  await _displayMessageNotification(plugin, message.data);
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

      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_pushChannel);

      // If the app was fully terminated, tapping our tray notification just
      // cold-starts it fresh — `onDidReceiveNotificationResponse` above only
      // fires while the plugin's engine is already alive (foreground or
      // backgrounded-but-running), and `getInitialMessage()` below never
      // recognizes these taps either, since these are data-only FCM messages
      // with no native `notification` payload, so Android/FCM never tags the
      // launch as notification-caused. `getNotificationAppLaunchDetails()` is
      // the only API that can tell us this cold start was caused by tapping
      // one of our own locally-shown notifications, and hand back its payload.
      final launchDetails = await _localNotifications.getNotificationAppLaunchDetails();
      final launchPayload = launchDetails?.notificationResponse?.payload;
      if (launchDetails?.didNotificationLaunchApp == true && launchPayload != null) {
        _handleTap(Map<String, dynamic>.from(jsonDecode(launchPayload)));
      }

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
    _displayMessageNotification(_localNotifications, message.data);
  }

  // Dismisses the tray notification for a chat, e.g. once its messages have
  // been read — whether that happened by tapping the notification itself or
  // by opening the chat some other way through the app.
  static Future<void> cancelForChat(String chatId) async {
    await _localNotifications.cancel(_notificationIdForChat(chatId));
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
